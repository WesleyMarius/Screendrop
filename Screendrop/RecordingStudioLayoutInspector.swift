//
//  RecordingStudioLayoutInspector.swift
//  Screendrop
//
//  The camera layout picker: a grid of the layout presets, each drawn by
//  the same resolver the canvas uses so a tile is a true miniature of the
//  result, and the few options that apply to the picked layout. Used for
//  the default layout in the Camera section and for a layout cue selected
//  on the timeline.
//

import SwiftUI

struct StudioCameraLayoutPicker: View {
    @Bindable var model: RecordingStudioModel
    let layout: RecordingCameraLayout
    /// `isContinuous` is true while a slider is being dragged.
    let onChange: (RecordingCameraLayout, _ isContinuous: Bool) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: InspectorMetrics.rowSpacing, alignment: .top),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.groupSpacing) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                ForEach(RecordingCameraLayout.presets, id: \.self) { preset in
                    let candidate = layout.adopting(preset)
                    VStack(spacing: 4) {
                        InspectorTile(
                            title: preset.detailedTitle,
                            aspectRatio: tileAspect,
                            isSelected: layout.matches(preset: preset),
                            action: {
                                guard candidate != layout else { return }
                                onChange(candidate, false)
                            }
                        ) {
                            StudioCameraLayoutSchematic(model: model, layout: candidate)
                        }
                        Text(preset.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(layout.matches(preset: preset) ? Palette.label : Palette.secondaryLabel)
                            .lineLimit(1)
                    }
                }
            }

            options
        }
    }

    /// Tiles share the canvas's shape, so a portrait export shows portrait
    /// miniatures.
    private var tileAspect: CGFloat {
        let size = model.basePreviewCanvasSize
        guard size.width > 0, size.height > 0 else { return 16 / 10 }
        return min(max(size.width / size.height, 0.75), 2)
    }

    @ViewBuilder
    private var options: some View {
        switch layout.kind {
        case .pictureInPicture:
            VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
                    InspectorGroupLabel("Corner")
                    InspectorSegmented(
                        options: RecordingCameraLayout.Corner.allCases,
                        isSelected: { $0 == layout.corner },
                        onTap: { corner in
                            var next = layout
                            next.corner = corner
                            onChange(next, false)
                        },
                        label: { corner in
                            Image(systemName: corner.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .help(corner.title)
                        }
                    )
                }

                InspectorFieldPair {
                    InspectorSlider(
                        "Size",
                        value: Binding(
                            get: { CGFloat(layout.size) },
                            set: { value in
                                var next = layout
                                next.size = Double(value)
                                onChange(next, true)
                            }
                        ),
                        range: CGFloat(RecordingCameraLayout.sizeRange.lowerBound)...CGFloat(RecordingCameraLayout.sizeRange.upperBound),
                        format: .percent()
                    )
                } trailing: {
                    roundingSlider
                        .disabled(layout.shape == .circle)
                        .opacity(layout.shape == .circle ? 0.4 : 1)
                }
            }
        case .split:
            InspectorFieldPair {
                InspectorSlider(
                    "Width",
                    value: Binding(
                        get: { CGFloat(layout.splitRatio) },
                        set: { value in
                            var next = layout
                            next.splitRatio = Double(value)
                            onChange(next, true)
                        }
                    ),
                    range: CGFloat(RecordingCameraLayout.splitRatioRange.lowerBound)...CGFloat(RecordingCameraLayout.splitRatioRange.upperBound),
                    format: .percent()
                )
            } trailing: {
                EmptyView()
            }
        case .screen, .camera:
            EmptyView()
        }
    }

    /// Rounding is one setting for every rectangular camera, so a cue and
    /// the default never disagree about it.
    private var roundingSlider: some View {
        InspectorSlider(
            "Rounding",
            value: $model.style.camera.roundness,
            range: 0.05...0.5,
            format: .percent()
        )
    }
}

/// A miniature of a layout on the current canvas: the screen card with a
/// pointer, the camera with a person.
struct StudioCameraLayoutSchematic: View {
    @Bindable var model: RecordingStudioModel
    let layout: RecordingCameraLayout

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let base = RecordingStudioLayout.make(
                canvasSize: size,
                style: model.style,
                contentAspect: model.sourceVideoAspect,
                contentMode: .fit,
                contentCropRect: model.videoCropRect
            )
            let frame = RecordingCameraLayoutResolver(base: base, style: model.style, showsCamera: true)
                .frame(for: layout)
            let short = min(size.width, size.height)

            ZStack(alignment: .topLeading) {
                Palette.fill

                if frame.screenOpacity > 0.001 {
                    let card = frame.screenRect
                    RoundedRectangle(cornerRadius: max(2, base.cardCornerRadius), style: .continuous)
                        .fill(Color.primary.opacity(0.13))
                        .overlay {
                            Image(systemName: "cursorarrow")
                                .font(.system(size: max(7, min(card.width, card.height) * 0.3), weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.45))
                        }
                        .frame(width: card.width, height: card.height)
                        .offset(x: card.minX, y: card.minY)
                }

                let camera = frame.cameraRect
                if frame.cameraOpacity > 0.001, camera.width > 0 {
                    RoundedRectangle(cornerRadius: frame.cameraCornerRadius, style: .continuous)
                        .fill(Palette.accent.opacity(0.85))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: max(6, min(camera.width, camera.height) * 0.5)))
                                .foregroundStyle(Palette.onAccent.opacity(0.9))
                                .offset(y: min(camera.width, camera.height) * 0.08)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: frame.cameraCornerRadius, style: .continuous))
                        .frame(width: camera.width, height: camera.height)
                        .offset(x: camera.minX, y: camera.minY)
                }
            }
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(short <= 0)
        }
    }
}

extension RecordingCameraLayout.Corner {
    var title: String {
        switch self {
        case .topLeading: "Top left"
        case .topTrailing: "Top right"
        case .bottomLeading: "Bottom left"
        case .bottomTrailing: "Bottom right"
        }
    }

    var systemImage: String {
        switch self {
        case .topLeading: "arrow.up.left"
        case .topTrailing: "arrow.up.right"
        case .bottomLeading: "arrow.down.left"
        case .bottomTrailing: "arrow.down.right"
        }
    }
}
