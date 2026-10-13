//
//  RecordingCameraLayout.swift
//  Screendrop
//
//  Camera layouts: how the screen card and the camera share the canvas.
//  A project has a default layout and any number of layout cues on the
//  timeline. Each layout resolves to a frame (where the screen card and
//  the camera sit, their corners and opacities) and the timeline morphs
//  from one frame to the next at every cue boundary, so the camera can
//  fill the canvas for an intro and then shrink into its corner when the
//  screen takes over. Preview and export resolve the same frames.
//

import CoreGraphics
import Foundation

// MARK: - Layout

nonisolated struct RecordingCameraLayout: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// The screen alone; the camera is off.
        case screen
        /// The camera fills the frame; the screen is hidden.
        case camera
        /// The screen with the camera in one of its corners.
        case pictureInPicture
        /// The screen and a tall camera card side by side (stacked on a
        /// portrait canvas).
        case split
    }

    enum Corner: String, Codable, CaseIterable, Sendable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    enum Shape: String, Codable, CaseIterable, Sendable {
        case circle
        case square
        /// 3:4, taller than wide.
        case portrait
    }

    enum Side: String, Codable, CaseIterable, Sendable {
        /// Left on a landscape canvas, top on a portrait one.
        case leading
        case trailing
    }

    /// How the screen takes the space a split gives it.
    enum ScreenFit: String, Codable, CaseIterable, Sendable {
        /// The whole recording, letterboxed by the camera card's height.
        case fit
        /// Both cards fill the frame's height; the recording is cropped.
        case fill
    }

    static let sizeRange: ClosedRange<Double> = 0.12...0.45
    static let splitRatioRange: ClosedRange<Double> = 0.45...1.2
    static let spacingRange: ClosedRange<Double> = 0...0.12

    var kind: Kind
    var corner: Corner
    var shape: Shape
    /// Picture-in-picture camera width as a fraction of the canvas's
    /// smaller dimension.
    var size: Double
    var side: Side
    /// Split camera width over its height (landscape), or height over width
    /// (portrait canvas).
    var splitRatio: Double
    var screenFit: ScreenFit
    /// Split: one gap, as a fraction of the canvas's smaller dimension,
    /// around the frame and between the two cards.
    var spacing: Double

    init(
        kind: Kind = .pictureInPicture,
        corner: Corner = .bottomTrailing,
        shape: Shape = .square,
        size: Double = 0.26,
        side: Side = .trailing,
        splitRatio: Double = 0.75,
        screenFit: ScreenFit = .fill,
        spacing: Double = 0.04
    ) {
        self.kind = kind
        self.corner = corner
        self.shape = shape
        self.size = Self.clamped(size, to: Self.sizeRange, fallback: 0.26)
        self.side = side
        self.splitRatio = Self.clamped(splitRatio, to: Self.splitRatioRange, fallback: 0.75)
        self.screenFit = screenFit
        self.spacing = Self.clamped(spacing, to: Self.spacingRange, fallback: 0.04)
    }

    static let screenOnly = RecordingCameraLayout(kind: .screen)
    static let cameraOnly = RecordingCameraLayout(kind: .camera)

    var showsCamera: Bool { kind != .screen }
    var showsScreen: Bool { kind != .camera }

    /// The arrangement only: two layouts with the same preset differ only in
    /// options the preset doesn't fix (corner, size, a split's side).
    func matches(preset: RecordingCameraLayout) -> Bool {
        guard kind == preset.kind else { return false }
        return kind != .pictureInPicture || shape == preset.shape
    }

    /// Applies a preset picked from the grid while keeping the options the
    /// user already tuned (corner, size, split side and width).
    func adopting(_ preset: RecordingCameraLayout) -> RecordingCameraLayout {
        var next = self
        next.kind = preset.kind
        if preset.kind == .pictureInPicture {
            next.shape = preset.shape
        }
        return next
    }

    private enum CodingKeys: String, CodingKey {
        case kind, corner, shape, size, side, splitRatio, screenFit, spacing
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown values from a newer build fall back instead of failing
        // the whole project.
        func value<Value: RawRepresentable>(_ key: CodingKeys) -> Value? where Value.RawValue == String {
            guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
            return Value(rawValue: raw)
        }
        let kind: Kind? = value(.kind)
        let corner: Corner? = value(.corner)
        let shape: Shape? = value(.shape)
        let side: Side? = value(.side)
        let screenFit: ScreenFit? = value(.screenFit)
        self.init(
            kind: kind ?? .pictureInPicture,
            corner: corner ?? .bottomTrailing,
            shape: shape ?? .square,
            size: try container.decodeIfPresent(Double.self, forKey: .size) ?? 0.26,
            side: side ?? .trailing,
            splitRatio: try container.decodeIfPresent(Double.self, forKey: .splitRatio) ?? 0.75,
            screenFit: screenFit ?? .fill,
            spacing: try container.decodeIfPresent(Double.self, forKey: .spacing) ?? 0.04
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(corner.rawValue, forKey: .corner)
        try container.encode(shape.rawValue, forKey: .shape)
        try container.encode(size, forKey: .size)
        try container.encode(side.rawValue, forKey: .side)
        try container.encode(splitRatio, forKey: .splitRatio)
        try container.encode(screenFit.rawValue, forKey: .screenFit)
        try container.encode(spacing, forKey: .spacing)
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

extension RecordingCameraLayout {
    /// The layout grid, in reading order.
    static let presets: [RecordingCameraLayout] = [
        .screenOnly,
        .cameraOnly,
        RecordingCameraLayout(kind: .pictureInPicture, shape: .square),
        RecordingCameraLayout(kind: .pictureInPicture, shape: .circle),
        RecordingCameraLayout(kind: .pictureInPicture, shape: .portrait),
        RecordingCameraLayout(kind: .split)
    ]

    var title: String {
        switch kind {
        case .screen: "Screen"
        case .camera: "Camera"
        case .pictureInPicture:
            switch shape {
            case .circle: "Circle"
            case .square: "Bubble"
            case .portrait: "Portrait"
            }
        case .split: "Split"
        }
    }

    /// Spelled out for help tags and menus.
    var detailedTitle: String {
        switch kind {
        case .screen: "Screen only"
        case .camera: "Camera full frame"
        case .pictureInPicture: "Screen with \(title.lowercased()) camera"
        case .split: "Screen and camera side by side"
        }
    }

    var systemImage: String {
        switch kind {
        case .screen: "rectangle"
        case .camera: "person.crop.rectangle"
        case .pictureInPicture: shape == .circle ? "pip" : "rectangle.inset.bottomright.filled"
        case .split: "rectangle.split.2x1"
        }
    }

    /// Migrates the free-form bubble of projects saved before layouts: the
    /// nearest corner, its size, and a circle when it was fully rounded.
    static func migrated(center: CGPoint, size: Double, roundness: Double) -> RecordingCameraLayout {
        let corner: Corner = switch (center.x < 0.5, center.y < 0.5) {
        case (true, true): .topLeading
        case (false, true): .topTrailing
        case (true, false): .bottomLeading
        case (false, false): .bottomTrailing
        }
        return RecordingCameraLayout(
            kind: .pictureInPicture,
            corner: corner,
            shape: roundness >= 0.49 ? .circle : .square,
            size: size
        )
    }

    /// Normalized canvas center the bubble roughly occupies, written beside
    /// the layout so older builds still open the project sensibly.
    var legacyCenter: CGPoint {
        let near = 0.15, far = 0.85
        return switch corner {
        case .topLeading: CGPoint(x: near, y: near)
        case .topTrailing: CGPoint(x: far, y: near)
        case .bottomLeading: CGPoint(x: near, y: far)
        case .bottomTrailing: CGPoint(x: far, y: far)
        }
    }

    /// The layout a new cue starts with, given the layout it interrupts:
    /// usually "the other one" - the camera when the screen has the floor.
    static func suggestedCue(over base: RecordingCameraLayout) -> RecordingCameraLayout {
        switch base.kind {
        case .camera: base.adopting(RecordingCameraLayout(kind: .pictureInPicture))
        case .screen, .pictureInPicture, .split: base.adopting(.cameraOnly)
        }
    }
}

// MARK: - Cues

/// A stretch of the recording shown in a layout other than the default.
/// Times are source seconds, like zoom cues, so cuts and speed changes
/// carry the cue with the footage it was placed on.
nonisolated struct RecordingCameraLayoutCue: Identifiable, Codable, Equatable, Sendable {
    static let minimumDuration: TimeInterval = 0.5

    var id: UUID
    var start: TimeInterval
    var end: TimeInterval
    var layout: RecordingCameraLayout

    init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, layout: RecordingCameraLayout) {
        self.id = id
        self.start = start
        self.end = end
        self.layout = layout
    }

    var duration: TimeInterval { max(0, end - start) }
}

/// One cue as the timeline draws it, in editor time.
nonisolated struct RecordingCameraLayoutTimelineBlock: Identifiable, Equatable, Sendable {
    let cue: RecordingCameraLayoutCue
    let editorStart: TimeInterval
    let editorEnd: TimeInterval

    var id: UUID { cue.id }
}

// MARK: - Frames

/// Where everything sits at one moment, in top-left canvas points.
nonisolated struct RecordingCameraLayoutFrame: Equatable, Sendable {
    /// The resting card's aspect, except in a fill split, where the
    /// content covers it and is cropped.
    var screenRect: CGRect
    var screenOpacity: CGFloat
    var cameraRect: CGRect
    var cameraCornerRadius: CGFloat
    var cameraOpacity: CGFloat

    /// Blends two frames. Something hidden at one end appears from (or
    /// leaves into) a slightly smaller copy of where it sits at the other,
    /// so it settles in place instead of flying in from nowhere.
    static func interpolate(
        _ from: RecordingCameraLayoutFrame,
        _ to: RecordingCameraLayoutFrame,
        progress: CGFloat
    ) -> RecordingCameraLayoutFrame {
        let t = min(max(progress, 0), 1)
        var from = from
        var to = to
        if from.screenOpacity <= 0.001 { from.screenRect = to.screenRect.scaledAboutCenter(0.94) }
        if to.screenOpacity <= 0.001 { to.screenRect = from.screenRect.scaledAboutCenter(0.94) }
        if from.cameraOpacity <= 0.001 {
            from.cameraRect = to.cameraRect.scaledAboutCenter(0.82)
            from.cameraCornerRadius = to.cameraCornerRadius * 0.82
        }
        if to.cameraOpacity <= 0.001 {
            to.cameraRect = from.cameraRect.scaledAboutCenter(0.82)
            to.cameraCornerRadius = from.cameraCornerRadius * 0.82
        }
        // Fades run in the first part of the move, so a layer arriving is
        // solid well before it lands and one leaving is gone before it stops.
        let fade = min(t / 0.6, 1)
        return RecordingCameraLayoutFrame(
            screenRect: from.screenRect.lerp(to: to.screenRect, t),
            screenOpacity: from.screenOpacity.lerp(to: to.screenOpacity, fade),
            cameraRect: from.cameraRect.lerp(to: to.cameraRect, t),
            cameraCornerRadius: from.cameraCornerRadius.lerp(to: to.cameraCornerRadius, t),
            cameraOpacity: from.cameraOpacity.lerp(to: to.cameraOpacity, fade)
        )
    }
}

/// Resolves layouts against one canvas. Built from the resting layout (the
/// card the style and video crop produce), which every layout scales and
/// moves rather than reshapes.
nonisolated struct RecordingCameraLayoutResolver: Sendable {
    let base: RecordingStudioLayout
    let showsCamera: Bool
    private let contentArea: CGRect
    private let minDimension: CGFloat
    private let roundness: CGFloat
    private let margin: CGFloat
    /// The corner camera's scale once a zoom lands; 1 when it doesn't shrink.
    let zoomedCameraScale: CGFloat

    init(base: RecordingStudioLayout, style: RecordingStudioStyle, showsCamera: Bool) {
        self.base = base
        self.showsCamera = showsCamera
        let canvas = base.canvasSize
        minDimension = max(1, min(canvas.width, canvas.height))
        let inset = min(max(style.padding, 0), 0.475) * minDimension
        contentArea = CGRect(origin: .zero, size: canvas).insetBy(dx: inset, dy: inset)
        roundness = min(max(style.camera.roundness, 0), 0.5)
        margin = RecordingStudioLayout.bubbleMargin(forMinDimension: minDimension)
        zoomedCameraScale = style.camera.shrinksDuringZoom ? 1 - style.camera.zoomShrinkAmount : 1
    }

    /// A corner camera's scale for how far the screen has zoomed: full
    /// size unzoomed, `zoomedCameraScale` once the zoom lands, and in
    /// between on the zoom's own spring, so the two arrive together. The
    /// talking head has the floor until something happens on screen.
    func cameraScale(forZoomProgress progress: Double) -> CGFloat {
        let t = CGFloat(min(max(progress, 0), 1))
        return 1 - (1 - zoomedCameraScale) * t
    }

    /// `zoomProgress` is how far the screen has zoomed at that moment
    /// (ViewportTimeline.zoomProgress), which a corner camera shrinks with.
    func frame(for layout: RecordingCameraLayout, zoomProgress: Double = 0) -> RecordingCameraLayoutFrame {
        let card = base.cardRect
        let layout = showsCamera ? layout : .screenOnly
        switch layout.kind {
        case .screen:
            var hidden = RecordingCameraLayout(kind: .pictureInPicture)
            hidden.corner = layout.corner
            let ghost = pipCamera(for: hidden, in: card)
            return RecordingCameraLayoutFrame(
                screenRect: card,
                screenOpacity: 1,
                cameraRect: ghost.rect,
                cameraCornerRadius: ghost.radius,
                cameraOpacity: 0
            )
        case .camera:
            return RecordingCameraLayoutFrame(
                screenRect: card,
                screenOpacity: 0,
                cameraRect: contentArea,
                cameraCornerRadius: base.cardCornerRadius,
                cameraOpacity: 1
            )
        case .pictureInPicture:
            let camera = pipCamera(for: layout, in: card, scale: cameraScale(forZoomProgress: zoomProgress))
            return RecordingCameraLayoutFrame(
                screenRect: card,
                screenOpacity: 1,
                cameraRect: camera.rect,
                cameraCornerRadius: camera.radius,
                cameraOpacity: 1
            )
        case .split:
            let split = splitRects(for: layout)
            return RecordingCameraLayoutFrame(
                screenRect: split.screen,
                screenOpacity: 1,
                cameraRect: split.camera,
                cameraCornerRadius: base.cardCornerRadius,
                cameraOpacity: 1
            )
        }
    }

    func frame(
        for state: RecordingCameraLayoutTimeline.State,
        zoomProgress: Double = 0
    ) -> RecordingCameraLayoutFrame {
        switch state {
        case .settled(let layout):
            return frame(for: layout, zoomProgress: zoomProgress)
        case .transition(let from, let to, let progress):
            return .interpolate(
                frame(for: from, zoomProgress: zoomProgress),
                frame(for: to, zoomProgress: zoomProgress),
                progress: CGFloat(RecordingCameraLayoutTimeline.ease(progress))
            )
        }
    }

    /// The resting layout moved into a frame.
    func layout(
        for state: RecordingCameraLayoutTimeline.State,
        zoomProgress: Double = 0
    ) -> RecordingStudioLayout {
        base.applying(frame(for: state, zoomProgress: zoomProgress))
    }

    /// The camera tucked into a corner of the screen card.
    private func pipCamera(
        for layout: RecordingCameraLayout,
        in card: CGRect,
        scale: CGFloat = 1
    ) -> (rect: CGRect, radius: CGFloat) {
        let requested = CGFloat(layout.size) * minDimension
        let aspect: CGFloat = layout.shape == .portrait ? 3 / 4 : 1
        // Never let the camera outgrow the card it sits in.
        let maxWidth = max(24, min(card.width - margin * 2, (card.height - margin * 2) * aspect) * 0.62)
        // Shrinks toward its corner: the margins stay put.
        let width = max(24, min(requested, maxWidth)) * scale
        let size = CGSize(width: width, height: width / aspect)
        let x: CGFloat = switch layout.corner {
        case .topLeading, .bottomLeading: card.minX + margin
        case .topTrailing, .bottomTrailing: card.maxX - margin - size.width
        }
        let y: CGFloat = switch layout.corner {
        case .topLeading, .topTrailing: card.minY + margin
        case .bottomLeading, .bottomTrailing: card.maxY - margin - size.height
        }
        let short = min(size.width, size.height)
        let radius = layout.shape == .circle ? short / 2 : max(4, roundness * short)
        return (CGRect(origin: CGPoint(x: x, y: y), size: size), radius)
    }

    /// The screen card and a camera card side by side (stacked on a
    /// portrait canvas), with one spacing around the pair and between
    /// them. Fill gives both cards the frame's full height and lets the
    /// screen take the rest of the width, cropping the recording; Fit keeps
    /// the whole recording and matches the camera's height to it.
    private func splitRects(for layout: RecordingCameraLayout) -> (screen: CGRect, camera: CGRect) {
        let canvas = CGRect(origin: .zero, size: base.canvasSize)
        let gap = CGFloat(layout.spacing) * minDimension
        let area = canvas.insetBy(dx: min(gap, canvas.width / 4), dy: min(gap, canvas.height / 4))
        let card = base.cardRect
        let aspect = card.height > 0 ? max(0.1, card.width / card.height) : 16 / 9
        let ratio = CGFloat(layout.splitRatio)
        let cameraFirst = layout.side == .leading
        let fills = layout.screenFit == .fill

        if area.width >= area.height {
            let screenSize: CGSize
            let cameraSize: CGSize
            if fills {
                let height = area.height
                let cameraWidth = min(height * ratio, area.width * 0.6)
                cameraSize = CGSize(width: cameraWidth, height: height)
                screenSize = CGSize(width: max(1, area.width - gap - cameraWidth), height: height)
            } else {
                let height = max(1, min(area.height, (area.width - gap) / (aspect + ratio)))
                screenSize = CGSize(width: height * aspect, height: height)
                cameraSize = CGSize(width: height * ratio, height: height)
            }
            let total = screenSize.width + gap + cameraSize.width
            let x = area.midX - total / 2
            let y = area.midY - screenSize.height / 2
            let screenX = cameraFirst ? x + cameraSize.width + gap : x
            let cameraX = cameraFirst ? x : x + screenSize.width + gap
            return (
                CGRect(origin: CGPoint(x: screenX, y: y), size: screenSize),
                CGRect(origin: CGPoint(x: cameraX, y: y), size: cameraSize)
            )
        }

        let screenSize: CGSize
        let cameraSize: CGSize
        if fills {
            let width = area.width
            let cameraHeight = min(width * ratio, area.height * 0.6)
            cameraSize = CGSize(width: width, height: cameraHeight)
            screenSize = CGSize(width: width, height: max(1, area.height - gap - cameraHeight))
        } else {
            let width = max(1, min(area.width, (area.height - gap) / (1 / aspect + ratio)))
            screenSize = CGSize(width: width, height: width / aspect)
            cameraSize = CGSize(width: width, height: width * ratio)
        }
        let total = screenSize.height + gap + cameraSize.height
        let x = area.midX - screenSize.width / 2
        let y = area.midY - total / 2
        let screenY = cameraFirst ? y + cameraSize.height + gap : y
        let cameraY = cameraFirst ? y : y + screenSize.height + gap
        return (
            CGRect(origin: CGPoint(x: x, y: screenY), size: screenSize),
            CGRect(origin: CGPoint(x: x, y: cameraY), size: cameraSize)
        )
    }
}

extension RecordingStudioLayout {
    /// This layout with its card and camera moved into `frame`. The content
    /// scales uniformly to cover the new card - exactly when the card keeps
    /// its shape, cropping the overflow when a fill split reshapes it - so
    /// zoom and cursor math carry over unchanged.
    nonisolated func applying(_ frame: RecordingCameraLayoutFrame) -> RecordingStudioLayout {
        let scale = cardRect.width > 0 && cardRect.height > 0
            ? max(frame.screenRect.width / cardRect.width, frame.screenRect.height / cardRect.height)
            : 1
        return RecordingStudioLayout(
            canvasSize: canvasSize,
            cardRect: frame.screenRect,
            cardCornerRadius: cardCornerRadius,
            bubbleRect: frame.cameraRect,
            bubbleCornerRadius: frame.cameraCornerRadius,
            contentFillSize: CGSize(
                width: contentFillSize.width * scale,
                height: contentFillSize.height * scale
            ),
            screenOpacity: frame.screenOpacity,
            cameraOpacity: frame.cameraOpacity
        )
    }
}

// MARK: - Timeline

/// The default layout and every cue, resolved into change points on the
/// edited (editor-time) timeline. Each change morphs over a fixed length,
/// shortened when the next change comes sooner, so a morph always lands
/// before the next one begins.
nonisolated struct RecordingCameraLayoutTimeline: Equatable, Sendable {
    static let transitionDuration: TimeInterval = 0.6

    struct Change: Equatable, Sendable {
        let time: TimeInterval
        let from: RecordingCameraLayout
        let to: RecordingCameraLayout
        let duration: TimeInterval
    }

    enum State: Equatable, Sendable {
        case settled(RecordingCameraLayout)
        case transition(from: RecordingCameraLayout, to: RecordingCameraLayout, progress: Double)

        var settledLayout: RecordingCameraLayout? {
            if case .settled(let layout) = self { return layout }
            return nil
        }
    }

    let initial: RecordingCameraLayout
    let changes: [Change]

    static func constant(_ layout: RecordingCameraLayout) -> RecordingCameraLayoutTimeline {
        RecordingCameraLayoutTimeline(initial: layout, changes: [])
    }

    /// Every layout the timeline ever shows.
    var layouts: [RecordingCameraLayout] {
        [initial] + changes.map(\.to)
    }

    var usesCamera: Bool {
        layouts.contains(where: \.showsCamera)
    }

    static func blocks(
        for cues: [RecordingCameraLayoutCue],
        clipTimeline: RecordingClipTimeline
    ) -> [RecordingCameraLayoutTimelineBlock] {
        cues.compactMap { cue in
            let slices = clipTimeline.slices(overlapping: cue.start, sourceEnd: cue.end)
            guard let first = slices.first, let last = slices.last else { return nil }
            return RecordingCameraLayoutTimelineBlock(
                cue: cue,
                editorStart: first.editorStart,
                editorEnd: last.editorEnd
            )
        }
        .sorted { $0.editorStart < $1.editorStart }
    }

    static func build(
        defaultLayout: RecordingCameraLayout,
        cues: [RecordingCameraLayoutCue],
        clipTimeline: RecordingClipTimeline
    ) -> RecordingCameraLayoutTimeline {
        build(defaultLayout: defaultLayout, blocks: blocks(for: cues, clipTimeline: clipTimeline))
    }

    static func build(
        defaultLayout: RecordingCameraLayout,
        blocks: [RecordingCameraLayoutTimelineBlock]
    ) -> RecordingCameraLayoutTimeline {
        var initial = defaultLayout
        var points: [(time: TimeInterval, layout: RecordingCameraLayout)] = []
        var cursor: TimeInterval = 0
        var hasBlock = false
        for block in blocks where block.editorEnd > block.editorStart {
            let start = max(block.editorStart, cursor)
            guard block.editorEnd > start else { continue }
            // A gap after a cue returns to the default until the next one.
            if hasBlock, start > cursor {
                points.append((cursor, defaultLayout))
            }
            if !hasBlock, start <= 0.0001 {
                initial = block.cue.layout
            } else {
                points.append((start, block.cue.layout))
            }
            hasBlock = true
            cursor = block.editorEnd
        }
        if hasBlock {
            points.append((cursor, defaultLayout))
        }

        var changes: [Change] = []
        var current = initial
        for (index, point) in points.enumerated() where point.layout != current {
            let next = points[(index + 1)...].first?.time ?? .infinity
            changes.append(Change(
                time: point.time,
                from: current,
                to: point.layout,
                duration: max(0, min(transitionDuration, next - point.time))
            ))
            current = point.layout
        }
        return RecordingCameraLayoutTimeline(initial: initial, changes: changes)
    }

    func state(at time: TimeInterval) -> State {
        // Last change at or before `time`.
        var low = 0
        var high = changes.count
        while low < high {
            let mid = (low + high) / 2
            if changes[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return .settled(initial) }
        let change = changes[low - 1]
        let elapsed = time - change.time
        guard change.duration > 0, elapsed < change.duration else { return .settled(change.to) }
        return .transition(from: change.from, to: change.to, progress: elapsed / change.duration)
    }

    /// The layout in effect at `time`, or the one being morphed into.
    func layout(at time: TimeInterval) -> RecordingCameraLayout {
        switch state(at: time) {
        case .settled(let layout): layout
        case .transition(_, let to, _): to
        }
    }

    /// A critically damped spring normalized to land exactly at 1: it
    /// leaves at rest, covers most of the way early, settles softly, and
    /// never overshoots.
    static func ease(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        let omega = 7.5
        let end = 1 - (1 + omega) * exp(-omega)
        return (1 - (1 + omega * t) * exp(-omega * t)) / end
    }
}

// MARK: - Geometry helpers

private extension CGFloat {
    nonisolated func lerp(to other: CGFloat, _ t: CGFloat) -> CGFloat {
        self + (other - self) * t
    }
}

private extension CGRect {
    nonisolated func lerp(to other: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: minX.lerp(to: other.minX, t),
            y: minY.lerp(to: other.minY, t),
            width: width.lerp(to: other.width, t),
            height: height.lerp(to: other.height, t)
        )
    }

    nonisolated func scaledAboutCenter(_ scale: CGFloat) -> CGRect {
        CGRect(
            x: midX - width * scale / 2,
            y: midY - height * scale / 2,
            width: width * scale,
            height: height * scale
        )
    }
}

// MARK: - Zooming inside a cropped card

/// A fill split shows only a slice of the screen recording. Its camera is
/// the same zoom timeline as everywhere else - one spring moving the zoom
/// and the framing together - built for that narrower slice, so a zoom
/// centres its target in what the card actually shows. Unzoomed it rests
/// still, exactly like the full-width card. Morphs blend between cameras
/// along with the layout.
nonisolated struct RecordingCameraLayoutZoom: Sendable {
    private let timelines: [RecordingCameraLayout: ViewportTimeline]

    static let none = RecordingCameraLayoutZoom(timelines: [:])

    /// `canvasSize` through `contentCropRect` must describe the resting
    /// layout exactly as the compositor builds it.
    static func build(
        canvasSize: CGSize,
        style: RecordingStudioStyle,
        usesUniformPadding: Bool,
        contentAspect: CGFloat?,
        contentMode: RecordingStudioLayout.ContentMode,
        contentCropRect: CGRect,
        showsCamera: Bool,
        layoutTimeline: RecordingCameraLayoutTimeline,
        cues: [ZoomCue],
        capture: PointerCaptureFile,
        clipTimeline: RecordingClipTimeline
    ) -> RecordingCameraLayoutZoom {
        let fills = Set(layoutTimeline.layouts.filter { $0.kind == .split && $0.screenFit == .fill })
        guard showsCamera, !fills.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return .none }
        let base = RecordingStudioLayout.make(
            canvasSize: canvasSize,
            style: style,
            usesUniformPadding: usesUniformPadding,
            contentAspect: contentAspect,
            contentMode: contentMode,
            contentCropRect: contentCropRect
        )
        let resolver = RecordingCameraLayoutResolver(base: base, style: style, showsCamera: true)
        var timelines: [RecordingCameraLayout: ViewportTimeline] = [:]
        for layout in fills {
            let applied = base.applying(resolver.frame(for: layout))
            guard applied.contentFillSize.width > 0, applied.contentFillSize.height > 0 else { continue }
            let visible = CGSize(
                width: applied.cardRect.width / applied.contentFillSize.width,
                height: applied.cardRect.height / applied.contentFillSize.height
            )
            // A card that still shows the whole recording uses the ordinary camera.
            guard visible.width < 0.999 || visible.height < 0.999 else { continue }
            timelines[layout] = ViewportTimeline.build(
                cues: cues,
                capture: capture,
                clipTimeline: clipTimeline,
                visibleFraction: visible
            )
        }
        return RecordingCameraLayoutZoom(timelines: timelines)
    }

    /// The camera at an editor time: a fill split's own zoom timeline while
    /// one shows, `base` elsewhere, blended across a morph.
    func viewport(
        at time: TimeInterval,
        state: RecordingCameraLayoutTimeline.State,
        base: (TimeInterval) -> ViewportFrame
    ) -> ViewportFrame {
        guard !timelines.isEmpty else { return base(time) }
        func camera(for layout: RecordingCameraLayout) -> ViewportFrame {
            timelines[layout]?.frame(at: time) ?? base(time)
        }
        switch state {
        case .settled(let layout):
            return camera(for: layout)
        case .transition(let from, let to, let progress):
            guard timelines[from] != nil || timelines[to] != nil else { return base(time) }
            let a = camera(for: from)
            let b = camera(for: to)
            let t = RecordingCameraLayoutTimeline.ease(progress)
            return ViewportFrame(
                magnification: a.magnification + (b.magnification - a.magnification) * t,
                anchor: CGPoint(
                    x: a.anchor.x + (b.anchor.x - a.anchor.x) * t,
                    y: a.anchor.y + (b.anchor.y - a.anchor.y) * t
                )
            )
        }
    }
}
