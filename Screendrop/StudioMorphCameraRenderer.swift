//
//  StudioMorphCameraRenderer.swift
//  Screendrop
//
//  The camera for an export frame inside a layout morph, drawn on the GPU
//  into the finished frame: its shadow, its shutter samples clipped to the
//  bubble, and its border. A morphing camera changes size every frame, so
//  nothing about it can be cached, and Core Graphics resampling the camera
//  and blurring its shadow at canvas size made morph frames ten times the
//  cost of settled ones.
//

import CoreGraphics
import CoreVideo
import Metal
import MetalPerformanceShaders

nonisolated final class StudioMorphCameraRenderer {
    /// The bubble in top-left canvas pixels.
    struct Bubble {
        var rect: CGRect
        var cornerRadius: CGFloat
        var opacity: CGFloat
        var borderWidth: CGFloat
        var borderAlpha: CGFloat
        var shadow: StudioMorphShadow
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let textureCache: CVMetalTextureCache
    private let downsampler: MPSImageLanczosScale
    private var downsampledTexture: MTLTexture?
    /// The camera frame `downsampledTexture` holds; a 30 fps camera repeats
    /// across 60 fps output frames. Retained so a recycled buffer can't match.
    private var downsampledSource: CVPixelBuffer?
    /// A copy of the frame under the camera, which the kernel composites over.
    private var belowTexture: MTLTexture?

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let function = device.makeDefaultLibrary()?.makeFunction(name: "studioMorphCamera"),
              let pipeline = try? device.makeComputePipelineState(function: function)
        else { return nil }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache
        else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.textureCache = cache
        self.downsampler = MPSImageLanczosScale(device: device)
        self.downsampler.edgeMode = .clamp
    }

    /// Composites the camera into `destination`, which the CPU must not
    /// have locked, and waits for it. `fillRects` are where the whole camera
    /// frame lands for each shutter sample, in top-left canvas pixels. False
    /// means nothing was drawn and the caller must draw the camera itself.
    func render(
        camera: CVPixelBuffer, fillRects: [CGRect], bubble: Bubble, into destination: CVPixelBuffer
    ) -> Bool {
        guard (1...24).contains(fillRects.count),
              fillRects.allSatisfy({
                  $0.width > 0 && $0.height > 0 && $0.minX.isFinite && $0.minY.isFinite
                      && $0.width.isFinite && $0.height.isFinite
              }),
              let source = texture(for: camera, usage: .shaderRead),
              let output = texture(for: destination, usage: [.shaderRead, .shaderWrite]),
              let sourceTexture = CVMetalTextureGetTexture(source),
              let outputTexture = CVMetalTextureGetTexture(output)
        else { return false }
        let canvas = CGRect(x: 0, y: 0, width: outputTexture.width, height: outputTexture.height)
        let margin = bubble.shadow.blur * 1.05 + bubble.shadow.offset + 2
        let region = bubble.rect.insetBy(dx: -margin, dy: -margin).intersection(canvas).integral
        guard !region.isNull, region.width >= 1, region.height >= 1,
              let below = belowTexture(width: outputTexture.width, height: outputTexture.height),
              let command = queue.makeCommandBuffer()
        else { return false }

        // Leave at most twice the drawn size for the kernel's Lanczos, as
        // the screen pass does, so a shrunken camera doesn't alias.
        var sampledTexture = sourceTexture
        let scaledWidth = Int(min(CGFloat(sourceTexture.width), ceil(fillRects.map(\.width).max()! * 2)))
        let scaledHeight = Int(min(CGFloat(sourceTexture.height), ceil(fillRects.map(\.height).max()! * 2)))
        if scaledWidth < sourceTexture.width || scaledHeight < sourceTexture.height {
            if downsampledTexture?.width != scaledWidth || downsampledTexture?.height != scaledHeight {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: scaledWidth, height: scaledHeight, mipmapped: false)
                descriptor.usage = [.shaderRead, .shaderWrite]
                descriptor.storageMode = .private
                downsampledTexture = device.makeTexture(descriptor: descriptor)
                downsampledSource = nil
            }
            guard let downsampledTexture else { return false }
            if downsampledSource !== camera {
                downsampler.encode(
                    commandBuffer: command, sourceTexture: sourceTexture, destinationTexture: downsampledTexture)
            }
            sampledTexture = downsampledTexture
        }
        guard fillRects.allSatisfy({
            $0.width * 4 >= CGFloat(sampledTexture.width) && $0.height * 4 >= CGFloat(sampledTexture.height)
        }) else { return false }

        let origin = MTLOrigin(x: Int(region.minX), y: Int(region.minY), z: 0)
        let size = MTLSize(width: Int(region.width), height: Int(region.height), depth: 1)
        guard let blit = command.makeBlitCommandEncoder() else { return false }
        blit.copy(
            from: outputTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin, sourceSize: size,
            to: below, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
        blit.endEncoding()

        guard let encoder = command.makeComputeCommandEncoder() else { return false }
        var count = UInt32(fillRects.count)
        let rects = fillRects.map { SIMD4<Float>(Float($0.minX), Float($0.minY), Float($0.width), Float($0.height)) }
        let shape: [SIMD4<Float>] = [
            SIMD4(Float(bubble.rect.minX), Float(bubble.rect.minY), Float(bubble.rect.width), Float(bubble.rect.height)),
            SIMD4(Float(bubble.cornerRadius), Float(bubble.opacity), Float(bubble.borderWidth), Float(bubble.borderAlpha)),
            bubble.shadow.parameters,
            SIMD4(Float(region.minX), Float(region.minY), 0, 0)
        ]
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(sampledTexture, index: 0)
        encoder.setTexture(below, index: 1)
        encoder.setTexture(outputTexture, index: 2)
        rects.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 1)
        shape.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 2) }
        let width = pipeline.threadExecutionWidth
        let height = min(8, pipeline.maxTotalThreadsPerThreadgroup / width)
        encoder.dispatchThreads(size, threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
        encoder.endEncoding()
        command.commit()
        downsampledSource = sampledTexture === downsampledTexture ? camera : nil
        withExtendedLifetime([source, output]) { command.waitUntilCompleted() }
        return command.status == .completed
    }

    private func belowTexture(width: Int, height: Int) -> MTLTexture? {
        if let belowTexture, belowTexture.width == width, belowTexture.height == height { return belowTexture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        belowTexture = device.makeTexture(descriptor: descriptor)
        return belowTexture
    }

    private func texture(for buffer: CVPixelBuffer, usage: MTLTextureUsage) -> CVMetalTexture? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        var texture: CVMetalTexture?
        let attributes = [kCVMetalTextureUsage: usage.rawValue] as CFDictionary
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, buffer, attributes, .bgra8Unorm,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &texture
        ) == kCVReturnSuccess else { return nil }
        return texture
    }
}
