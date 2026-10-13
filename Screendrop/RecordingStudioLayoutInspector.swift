//
//  RecordingStudioLayoutInspector.swift
//  Screendrop
//
//  The camera layout picker: a grid of the six layouts as quiet miniatures,
//  and below it only the options the picked layout has. Used for the
//  default layout in the Camera section and for a layout cue selected on
//  the timeline.
//

import SwiftUI

struct StudioCameraLayoutPicker: View {
    @Bindable var model: RecordingStudioModel
    let layout: RecordingCameraLayout
    /// `isContinuous` is true while a slider is being dragged.
    let onChange: (RecordingCameraLayout, _ isContinuous: Bool) -> Void

    private static let tileSpacing: CGFloat = 8
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Self.tileSpacing),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.groupSpacing) {
            LazyVGrid(columns: columns, spacing: Self.tileSpacing) {
                ForEach(RecordingCameraLayout.presets, id: \.self) { preset in
                    let candidate = layout.adopting(preset)
                    let isSelected = layout.matches(preset: preset)
                    InspectorTile(
                        title: preset.detailedTitle,
                        aspectRatio: tileAspect,
                        isSelected: isSelected,
                        action: {
                            guard candidate != layout else { return }
                            onChange(candidate, false)
                        }
                    ) {
                        StudioCameraLayoutSchematic(layout: candidate, isSelected: isSelected)
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
        return min(max(size.width / size.height, 0.75), 1.9)
    }

    @ViewBuilder
    private var options: some View {
        switch layout.kind {
        case .pictureInPicture:
            VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                group("Corner") {
                    InspectorSegmented(
                        options: RecordingCameraLayout.Corner.allCases,
                        isSelected: { $0 == layout.corner },
                        onTap: { corner in edit { $0.corner = corner } },
                        label: { corner in
                            Image(systemName: corner.systemImage)
                                .font(.system(size: 10.5, weight: .semibold))
                                .accessibilityLabel(corner.title)
                        }
                    )
                }

                InspectorFieldPair {
                    slider("Size", \.size, range: RecordingCameraLayout.sizeRange)
                } trailing: {
                    InspectorSlider(
                        "Rounding",
                        value: $model.style.camera.roundness,
                        range: 0.05...0.5,
                        format: .percent()
                    )
                    .disabled(layout.shape == .circle)
                    .opacity(layout.shape == .circle ? 0.4 : 1)
                }

                InspectorToggleRow(
                    "Shrink during zooms",
                    isOn: Binding(
                        get: { model.style.camera.shrinksDuringZoom },
                        set: { isOn in
                            withAnimation(.fold) { model.style.camera.shrinksDuringZoom = isOn }
                        }
                    )
                )
                .help("The camera steps back while the screen is zoomed in, and returns when it zooms out")

                if model.style.camera.shrinksDuringZoom {
                    InspectorSlider(
                        "Shrink",
                        value: $model.style.camera.zoomShrinkAmount,
                        range: RecordingCameraBubbleSettings.zoomShrinkAmountRange,
                        format: .percent()
                    )
                    .help("How much smaller the camera gets once a zoom lands")
                    .transition(.opacity)
                }
            }
        case .split:
            VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                InspectorFieldPair {
                    group("Camera") {
                        InspectorSegmented(
                            options: RecordingCameraLayout.Side.allCases,
                            isSelected: { $0 == layout.side },
                            onTap: { side in edit { $0.side = side } },
                            label: { Text($0.title(isPortrait: isPortraitCanvas)).font(.inspectorSegment) }
                        )
                    }
                } trailing: {
                    group("Screen") {
                        InspectorSegmented(
                            options: RecordingCameraLayout.ScreenFit.allCases,
                            isSelected: { $0 == layout.screenFit },
                            onTap: { fit in edit { $0.screenFit = fit } },
                            label: { Text($0.title).font(.inspectorSegment) }
                        )
                    }
                }

                InspectorFieldPair {
                    slider("Width", \.splitRatio, range: RecordingCameraLayout.splitRatioRange)
                } trailing: {
                    slider("Spacing", \.spacing, range: RecordingCameraLayout.spacingRange)
                        .help("The gap around the frame and between the screen and camera")
                }
            }
        case .screen, .camera:
            EmptyView()
        }
    }

    private var isPortraitCanvas: Bool {
        let size = model.basePreviewCanvasSize
        return size.height > size.width
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
            InspectorGroupLabel(title)
            content()
        }
    }

    private func edit(_ change: (inout RecordingCameraLayout) -> Void) {
        var next = layout
        change(&next)
        guard next != layout else { return }
        onChange(next, false)
    }

    private func slider(
        _ title: String,
        _ keyPath: WritableKeyPath<RecordingCameraLayout, Double>,
        range: ClosedRange<Double>
    ) -> some View {
        InspectorSlider(
            title,
            value: Binding(
                get: { CGFloat(layout[keyPath: keyPath]) },
                set: { value in
                    var next = layout
                    next[keyPath: keyPath] = Double(value)
                    onChange(next, true)
                }
            ),
            range: CGFloat(range.lowerBound)...CGFloat(range.upperBound),
            format: .percent()
        )
    }
}

/// A miniature of a layout, drawn by the real resolver on an idealized
/// frame so every tile shares one padding and one set of corners whatever
/// the project's own style. Neutral throughout; the camera takes the accent
/// on the selected tile.
struct StudioCameraLayoutSchematic: View {
    let layout: RecordingCameraLayout
    var isSelected = false

    private static let style: RecordingStudioStyle = {
        var style = RecordingStudioStyle(background: .none)
        style.padding = 0.1
        style.cornerRadius = 0.05
        style.camera.roundness = 0.3
        style.camera.shrinksDuringZoom = false
        return style
    }()

    /// Every tile keeps the same margins, so a split's own spacing doesn't
    /// make it look framed differently from its neighbours.
    private var miniature: RecordingCameraLayout {
        var miniature = layout
        miniature.spacing = 0.07
        return miniature
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let base = RecordingStudioLayout.make(
                canvasSize: size,
                style: Self.style,
                usesUniformPadding: true
            )
            let frame = RecordingCameraLayoutResolver(base: base, style: Self.style, showsCamera: true)
                .frame(for: miniature)
            let radius = base.cardCornerRadius

            ZStack(alignment: .topLeading) {
                Color.primary.opacity(0.035)

                if frame.screenOpacity > 0.001 {
                    let card = frame.screenRect
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.primary.opacity(0.09))
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                        }
                        .overlay {
                            Image(systemName: "cursorarrow")
                                .font(.system(size: max(6, min(card.width, card.height) * 0.22), weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.3))
                        }
                        .frame(width: card.width, height: card.height)
                        .offset(x: card.minX, y: card.minY)
                }

                let camera = frame.cameraRect
                if frame.cameraOpacity > 0.001, camera.width > 0 {
                    RoundedRectangle(cornerRadius: frame.cameraCornerRadius, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.primary.opacity(0.26)))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: max(5, min(camera.width, camera.height) * 0.42)))
                                .foregroundStyle(Color.white.opacity(0.92))
                                .offset(y: min(camera.width, camera.height) * 0.1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: frame.cameraCornerRadius, style: .continuous))
                        .frame(width: camera.width, height: camera.height)
                        .offset(x: camera.minX, y: camera.minY)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
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

extension RecordingCameraLayout.Side {
    func title(isPortrait: Bool) -> String {
        switch self {
        case .leading: isPortrait ? "Top" : "Left"
        case .trailing: isPortrait ? "Bottom" : "Right"
        }
    }
}

extension RecordingCameraLayout.ScreenFit {
    var title: String {
        switch self {
        case .fit: "Fit"
        case .fill: "Fill"
        }
    }
}
