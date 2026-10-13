//
//  RecordingStudioLayoutInspector.swift
//  Screendrop
//
//  The camera layout picker: a grid of the seven layouts as quiet miniatures,
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

                zoomShrinkControls
            }
        case .cutout:
            VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                group("Position") {
                    InspectorSegmented(
                        options: RecordingCameraLayout.Placement.allCases,
                        isSelected: { $0 == layout.placement },
                        onTap: { placement in edit { $0.placement = placement } },
                        label: { Text($0.title).font(.inspectorSegment) }
                    )
                }

                slider("Size", \.cutoutSize, range: RecordingCameraLayout.cutoutSizeRange)
                    .help("How tall the camera's picture stands, measured on the canvas's shorter side")

                zoomShrinkControls
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

    /// A camera over the screen steps back for zooms.
    @ViewBuilder
    private var zoomShrinkControls: some View {
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

/// One layout in the picker: a tiny scene sitting in a flat white card,
/// above its name. Every card looks the same; the ring marks the picked
/// one, and its camera bounces in.
private struct StudioCameraLayoutTile: View {
    let layout: RecordingCameraLayout
    let title: String
    let aspectRatio: CGFloat
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    private static let radius: CGFloat = 12
    /// The white margin between the card's edge and the scene's well.
    private static let cardInset: CGFloat = 3
    private static let wellRadius = radius - cardInset
    private static let ringGap: CGFloat = 3

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                StudioCameraLayoutScene(layout: layout, isSelected: isSelected, outerRadius: Self.wellRadius)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Self.wellRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.wellRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                    }
                    .padding(Self.cardInset)
                    .background { card }
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

    /// Flat, with a hairline edge and a barely-there lift that firms up a
    /// touch on hover.
    private var card: some View {
        let isDark = colorScheme == .dark
        let lifted = isHovering && !isSelected
        return RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .fill(isDark ? Color(white: 0.22) : Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(lifted ? 0.13 : 0.08), lineWidth: 0.5)
            }
            .shadow(
                color: .black.opacity(isDark ? 0.3 : (lifted ? 0.09 : 0.055)),
                radius: lifted ? 2.5 : 1.5,
                y: 1
            )
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
/// own style: a flat grey well, a little app window, and a camera with a
/// person in it.
struct StudioCameraLayoutScene: View {
    let layout: RecordingCameraLayout
    var isSelected = false
    /// The tile's corner radius; whatever sits inset from the tile's edge
    /// rounds concentrically with it.
    var outerRadius: CGFloat = 10

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

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
            let window = snapped(frame.screenRect)
            let camera = snapped(frame.cameraRect)
            let floats = layout.kind == .pictureInPicture

            ZStack(alignment: .topLeading) {
                backdrop

                if frame.screenOpacity > 0.001 {
                    MiniatureWindow(
                        radius: concentricRadius(for: window, in: size),
                        isDark: isDark,
                        pointer: pointer(in: window, clearOf: floats || layout.kind == .cutout ? camera : nil)
                    )
                    .frame(width: window.width, height: window.height)
                    .offset(x: window.minX, y: window.minY)
                }

                if frame.cameraOpacity > 0.001, camera.width > 0, layout.kind == .cutout {
                    MiniatureCutout(isDark: isDark)
                        .frame(width: camera.width, height: camera.height)
                        .modifier(SelectionBounce(isSelected: isSelected, anchor: .bottom))
                        .offset(x: camera.minX, y: camera.minY)
                } else if frame.cameraOpacity > 0.001, camera.width > 0 {
                    MiniatureCamera(
                        radius: floats ? frame.cameraCornerRadius : concentricRadius(for: camera, in: size),
                        isDark: isDark,
                        floats: floats
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

    /// On whole pixels, so hairlines and edges land crisp.
    private func snapped(_ rect: CGRect) -> CGRect {
        let scale = max(displayScale, 1)
        func round(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let minX = round(rect.minX), minY = round(rect.minY)
        return CGRect(x: minX, y: minY, width: round(rect.maxX) - minX, height: round(rect.maxY) - minY)
    }

    /// The pointer's tip, as a fraction of the window: in the content beside
    /// the sidebar, and on the far side from a camera standing over the
    /// window - above a cutout's shoulders.
    private func pointer(in window: CGRect, clearOf camera: CGRect?) -> CGPoint {
        guard let camera, window.width > 0 else { return CGPoint(x: 0.56, y: 0.5) }
        let offset = (camera.midX - window.midX) / window.width
        let x: CGFloat = offset > 0.05 ? 0.4 : (offset < -0.05 ? 0.7 : 0.22)
        return CGPoint(x: x, y: layout.kind == .cutout ? 0.4 : 0.5)
    }

    /// Outer radius = inner radius + padding, so a shape inset from the
    /// tile's edge keeps the tile's curve.
    private func concentricRadius(for rect: CGRect, in size: CGSize) -> CGFloat {
        let inset = min(rect.minX, rect.minY, size.width - rect.maxX, size.height - rect.maxY)
        return max(2, outerRadius - max(0, inset))
    }

    private var backdrop: some View {
        isDark ? Color(white: 0.14) : Color(white: 0.945)
    }
}

/// Pops the camera when its tile is picked.
private struct SelectionBounce: ViewModifier {
    let isSelected: Bool
    var anchor: UnitPoint = .center
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: anchor)
            .onChange(of: isSelected) { _, selected in
                guard selected else { return }
                withAnimation(.snappy(duration: 0.12)) { scale = 1.1 } completion: {
                    withAnimation(.bouncy(duration: 0.4, extraBounce: 0.15)) { scale = 1 }
                }
            }
    }
}

/// A tiny macOS window, as Tahoe draws one: the traffic lights on a sidebar
/// that floats inside the window, a heading over two lines of text, and the
/// pointer the recording is about. A window too narrow for a sidebar keeps
/// its lights on the window itself.
private struct MiniatureWindow: View {
    let radius: CGFloat
    let isDark: Bool
    /// Where the pointer's tip sits, as a fraction of the window.
    let pointer: CGPoint

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let unit = min(size.width, size.height)
            // A window about as narrow as it is tall, like a split's, has
            // no room for one.
            let showsSidebar = size.width > size.height * 1.2
            let inset = max(1, (unit * 0.04).rounded())
            let sidebarRadius = max(1, radius - inset)
            let sidebarWidth = (size.width * 0.27).rounded()
            let dot = max(2.25, unit * 0.06)
            // Far enough in that the corner never crowds the first light.
            let lightInset = max(dot * 0.85, (showsSidebar ? sidebarRadius : radius) * 0.5) + (showsSidebar ? inset : 0)
            let line = max(1.25, unit * 0.042)
            let textLeading = (showsSidebar ? inset + sidebarWidth : 0) + max(3, line * 2.6)
            let textWidth = size.width - textLeading - max(3, line * 2.6)

            ZStack(alignment: .topLeading) {
                isDark ? Color(white: 0.22) : Color.white

                if showsSidebar {
                    RoundedRectangle(cornerRadius: sidebarRadius, style: .continuous)
                        .fill(Color.primary.opacity(isDark ? 0.07 : 0.045))
                        .frame(width: sidebarWidth, height: size.height - inset * 2)
                        .offset(x: inset, y: inset)
                }

                MiniatureTrafficLights(dot: dot)
                    .offset(x: lightInset, y: lightInset)

                VStack(alignment: .leading, spacing: line * 1.2) {
                    Capsule()
                        .fill(Color.primary.opacity(isDark ? 0.26 : 0.17))
                        .frame(width: textWidth * 0.46, height: line * 1.35)
                    VStack(alignment: .leading, spacing: line * 0.9) {
                        ForEach([0.88, 0.66], id: \.self) { fraction in
                            Capsule()
                                .fill(Color.primary.opacity(isDark ? 0.12 : 0.085))
                                .frame(width: textWidth * fraction, height: line)
                        }
                    }
                }
                .offset(x: textLeading, y: lightInset + dot + line * 1.6)

                MiniaturePointer(height: max(6.5, unit * 0.2))
                    .offset(x: size.width * pointer.x, y: size.height * pointer.y)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isDark ? 0.1 : 0.07), lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(isDark ? 0.25 : 0.06), radius: 1.5, y: 0.5)
    }
}

/// Close, minimize and zoom, in macOS's colors and spacing.
private struct MiniatureTrafficLights: View {
    let dot: CGFloat

    var body: some View {
        HStack(spacing: dot * 0.66) {
            ForEach([Color(red: 1, green: 0.373, blue: 0.341),
                     Color(red: 0.996, green: 0.737, blue: 0.18),
                     Color(red: 0.157, green: 0.784, blue: 0.251)], id: \.self) { color in
                Circle().fill(color).frame(width: dot, height: dot)
            }
        }
    }
}

/// The macOS arrow, drawn rather than taken from a symbol so it stays a
/// crisp arrow at a few points tall: black, outlined in white, with its
/// tip at the view's origin.
private struct MiniaturePointer: View {
    let height: CGFloat

    var body: some View {
        let outline = max(0.6, height * 0.085)
        ZStack {
            Arrow().stroke(Color.white, style: StrokeStyle(lineWidth: outline * 2, lineJoin: .round))
            Arrow().fill(Color.black.opacity(0.85))
        }
        .frame(width: height * 0.58, height: height)
        .shadow(color: .black.opacity(0.18), radius: 0.6, y: 0.4)
    }

    private struct Arrow: Shape {
        func path(in rect: CGRect) -> Path {
            // The 11 x 19 system arrow, by its height.
            let points: [CGPoint] = [(0, 0), (0, 16), (4, 12.2), (6.8, 18.6), (9, 17.7), (6.3, 11.4), (11, 11.4)]
                .map { CGPoint(x: rect.minX + $0.0 / 19 * rect.height, y: rect.minY + $0.1 / 19 * rect.height) }
            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            return path
        }
    }
}

/// The camera: a person against a softly lit wall, cropped by the camera's
/// shape like a real webcam. A camera floating over the screen gets a white
/// rim and a deeper shadow; one laid out beside it is a card like the window.
private struct MiniatureCamera: View {
    let radius: CGFloat
    let isDark: Bool
    let floats: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Color(white: 0.39), Color(white: 0.33)]
                    : [Color(white: 0.87), Color(white: 0.805)],
                startPoint: .top,
                endPoint: .bottom
            )
            StudioPersonSilhouette()
                .fill(isDark ? Color(white: 0.8) : Color(white: 0.985))
        }
        .clipShape(shape)
        .overlay {
            if floats {
                shape.strokeBorder(Color.white.opacity(isDark ? 0.22 : 0.92), lineWidth: 0.75)
            } else {
                shape.strokeBorder(Color.primary.opacity(isDark ? 0.1 : 0.07), lineWidth: 0.5)
            }
        }
        .shadow(
            color: .black.opacity(isDark ? (floats ? 0.4 : 0.25) : (floats ? 0.13 : 0.06)),
            radius: floats ? 2 : 1.5,
            y: floats ? 0.75 : 0.5
        )
    }
}

/// The cutout: the same person with no camera around them, standing on the
/// canvas's bottom edge in front of the window with a soft shadow.
private struct MiniatureCutout: View {
    let isDark: Bool

    var body: some View {
        StudioPersonSilhouette()
            .fill(LinearGradient(
                colors: isDark
                    ? [Color(white: 0.6), Color(white: 0.52)]
                    : [Color(white: 0.73), Color(white: 0.655)],
                startPoint: .top,
                endPoint: .bottom
            ))
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.13), radius: 1.75, y: 0.5)
    }
}

/// Head and shoulders, drawn the way Apple's person glyph is: a round head
/// over domed shoulders. Sized by the frame's height - capped by its width,
/// so a tall card gets a person, not a wide one - centred where people sit
/// in front of a webcam, and always cropped by the frame's bottom edge.
struct StudioPersonSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let head = min(rect.height * 0.36, rect.width * 0.4)
        let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.41)
        let shouldersTop = center.y + head * 0.5 + head * 0.13
        var path = Path(ellipseIn: CGRect(
            x: center.x - head / 2, y: center.y - head / 2, width: head, height: head
        ))
        path.addPath(Path(
            roundedRect: CGRect(
                x: center.x - head * 0.95, y: shouldersTop,
                width: head * 1.9, height: rect.maxY - shouldersTop + head
            ),
            cornerRadius: head * 0.82,
            style: .continuous
        ))
        return path.intersection(Path(rect))
    }
}

extension RecordingCameraLayout.Placement {
    var title: String {
        switch self {
        case .leading: "Left"
        case .center: "Center"
        case .trailing: "Right"
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
