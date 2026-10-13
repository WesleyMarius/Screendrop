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

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.groupSpacing) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(RecordingCameraLayout.presets, id: \.self) { preset in
                    let candidate = layout.adopting(preset)
                    StudioCameraLayoutTile(
                        layout: candidate,
                        title: preset.title,
                        aspectRatio: tileAspect,
                        isSelected: layout.matches(preset: preset)
                    ) {
                        guard candidate != layout else { return }
                        onChange(candidate, false)
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

/// One layout in the picker: a tiny scene above its name. Unpicked scenes
/// rest muted; the picked one comes into colour and its camera bounces in.
private struct StudioCameraLayoutTile: View {
    let layout: RecordingCameraLayout
    let title: String
    let aspectRatio: CGFloat
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    private static let radius: CGFloat = 12
    private static let ringGap: CGFloat = 3

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                StudioCameraLayoutScene(layout: layout, isSelected: isSelected, outerRadius: Self.radius)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(isHovering && !isSelected ? 0.16 : 0.07), lineWidth: 0.5)
                    }
                    .saturation(isSelected ? 1 : isHovering ? 0.7 : 0.25)
                    .padding(Self.ringGap)
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.radius + Self.ringGap, style: .continuous)
                            .strokeBorder(InspectorControlPalette.selectionRing, lineWidth: 2)
                            .opacity(isSelected ? 1 : 0)
                    }

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Palette.label : Palette.secondaryLabel)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(StudioCameraLayoutTileButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .animation(.easeOut(duration: 0.22), value: isSelected)
        .help(layout.detailedTitle)
        .accessibilityLabel(layout.detailedTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct StudioCameraLayoutTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A layout drawn by the real resolver on an idealized frame, so every
/// tile shares one padding and one set of corners whatever the project's
/// own style: a soft backdrop, a little app window, and a camera with a
/// person in it.
struct StudioCameraLayoutScene: View {
    let layout: RecordingCameraLayout
    var isSelected = false
    /// The tile's corner radius; whatever sits inset from the tile's edge
    /// rounds concentrically with it.
    var outerRadius: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme

    private static let style: RecordingStudioStyle = {
        var style = RecordingStudioStyle(background: .none)
        style.padding = 0.08
        style.cornerRadius = 0.06
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
            let base = RecordingStudioLayout.make(canvasSize: size, style: Self.style, usesUniformPadding: true)
            let frame = RecordingCameraLayoutResolver(base: base, style: Self.style, showsCamera: true)
                .frame(for: miniature)

            ZStack(alignment: .topLeading) {
                backdrop

                if frame.screenOpacity > 0.001 {
                    MiniatureWindow(radius: concentricRadius(for: frame.screenRect, in: size), isDark: isDark)
                        .frame(width: frame.screenRect.width, height: frame.screenRect.height)
                        .offset(x: frame.screenRect.minX, y: frame.screenRect.minY)
                }

                let camera = frame.cameraRect
                if frame.cameraOpacity > 0.001, camera.width > 0 {
                    MiniatureCamera(
                        radius: layout.kind == .pictureInPicture
                            ? frame.cameraCornerRadius
                            : concentricRadius(for: camera, in: size),
                        isDark: isDark
                    )
                        .frame(width: camera.width, height: camera.height)
                        .modifier(SelectionBounce(isSelected: isSelected))
                        .offset(x: camera.minX, y: camera.minY)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }

    private var isDark: Bool { colorScheme == .dark }

    /// Outer radius = inner radius + padding, so a shape inset from the
    /// tile's edge keeps the tile's curve.
    private func concentricRadius(for rect: CGRect, in size: CGSize) -> CGFloat {
        let inset = min(rect.minX, rect.minY, size.width - rect.maxX, size.height - rect.maxY)
        return max(2, outerRadius - max(0, inset))
    }

    private var backdrop: some View {
        LinearGradient(
            colors: isDark
                ? [Color(red: 0.25, green: 0.22, blue: 0.33), Color(red: 0.33, green: 0.24, blue: 0.24)]
                : [Color(red: 0.86, green: 0.84, blue: 0.97), Color(red: 0.99, green: 0.87, blue: 0.80)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Pops the camera when its tile is picked.
private struct SelectionBounce: ViewModifier {
    let isSelected: Bool
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: isSelected) { _, selected in
                guard selected else { return }
                withAnimation(.snappy(duration: 0.12)) { scale = 1.1 } completion: {
                    withAnimation(.bouncy(duration: 0.4, extraBounce: 0.15)) { scale = 1 }
                }
            }
    }
}

/// A tiny app window: title bar with traffic lights, a sidebar, a few lines
/// of text, and the pointer the recording is about.
private struct MiniatureWindow: View {
    let radius: CGFloat
    let isDark: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let unit = min(size.width, size.height)
            let bar = max(4, unit * 0.14)
            let dot = bar * 0.42
            let line = max(1.5, unit * 0.045)
            let showsSidebar = size.width > size.height * 0.9

            ZStack(alignment: .topLeading) {
                (isDark ? Color(white: 0.17) : Color.white)

                HStack(spacing: dot * 0.55) {
                    ForEach([Color(red: 1, green: 0.37, blue: 0.34),
                             Color(red: 1, green: 0.74, blue: 0.18),
                             Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { color in
                        Circle().fill(color).frame(width: dot, height: dot)
                    }
                }
                .padding(.leading, bar * 0.45)
                .frame(height: bar)

                HStack(alignment: .top, spacing: 0) {
                    if showsSidebar {
                        Rectangle()
                            .fill(Color.primary.opacity(isDark ? 0.06 : 0.04))
                            .frame(width: size.width * 0.24)
                    }
                    VStack(alignment: .leading, spacing: line * 1.3) {
                        ForEach([0.72, 0.5, 0.62], id: \.self) { fraction in
                            Capsule()
                                .fill(Color.primary.opacity(isDark ? 0.16 : 0.1))
                                .frame(width: size.width * (showsSidebar ? 0.6 : 0.78) * fraction, height: line)
                        }
                    }
                    .padding(.top, line * 2)
                    .padding(.leading, line * 2.4)
                }
                .padding(.top, bar)

                Image(systemName: "cursorarrow")
                    .font(.system(size: max(6, unit * 0.17), weight: .semibold))
                    .foregroundStyle(isDark ? Color.white : Color.black.opacity(0.8))
                    .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
                    .position(x: size.width * (showsSidebar ? 0.55 : 0.5), y: size.height * 0.66)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .shadow(color: .black.opacity(isDark ? 0.35 : 0.12), radius: 3, y: 1.5)
    }
}

/// The camera: a person against a plain grey wall, cropped by the camera's shape
/// like a real webcam, with the export's light rim and soft shadow.
private struct MiniatureCamera: View {
    let radius: CGFloat
    let isDark: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let head = min(size.width, size.height) * 0.36
            let headY = size.height * 0.5 - head * 0.12

            ZStack {
                LinearGradient(
                    colors: isDark
                        ? [Color(white: 0.42), Color(white: 0.28)]
                        : [Color(white: 0.8), Color(white: 0.63)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Ellipse()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: head * 2.15, height: head * 1.4)
                    .position(x: size.width / 2, y: headY + head * 1.28)
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: head, height: head)
                    .position(x: size.width / 2, y: headY)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(isDark ? 0.4 : 0.2), radius: 3, y: 1.5)
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
