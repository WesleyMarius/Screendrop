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
                    MiniatureWindow(
                        radius: concentricRadius(for: frame.screenRect, in: size),
                        isDark: isDark,
                        pointer: layout.kind == .cutout ? pointerClear(of: frame.cameraRect, in: frame.screenRect) : nil
                    )
                        .frame(width: frame.screenRect.width, height: frame.screenRect.height)
                        .offset(x: frame.screenRect.minX, y: frame.screenRect.minY)
                }

                let camera = frame.cameraRect
                if frame.cameraOpacity > 0.001, camera.width > 0, layout.kind == .cutout {
                    MiniatureCutout(isDark: isDark)
                        .frame(width: camera.width, height: camera.height)
                        .modifier(SelectionBounce(isSelected: isSelected, anchor: .bottom))
                        .offset(x: camera.minX, y: camera.minY)
                } else if frame.cameraOpacity > 0.001, camera.width > 0 {
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

    /// Where in the window the pointer sits clear of a cutout standing in
    /// front of it: the side away from the person, above their shoulders.
    private func pointerClear(of camera: CGRect, in window: CGRect) -> CGPoint {
        let offset = (camera.midX - window.midX) / max(window.width, 1)
        let x: CGFloat = offset > 0.05 ? 0.32 : (offset < -0.05 ? 0.72 : 0.2)
        return CGPoint(x: x, y: 0.5)
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

/// A tiny app window: title bar with traffic lights, a sidebar, a few lines
/// of text, and the pointer the recording is about.
private struct MiniatureWindow: View {
    let radius: CGFloat
    let isDark: Bool
    /// The pointer's place as a fraction of the window, if not the middle.
    var pointer: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let unit = min(size.width, size.height)
            let dot = max(2.5, unit * 0.06)
            // Far enough in that the window's corner never clips the first
            // light, however round it is.
            let lightInset = max(dot * 0.9, radius * 0.45)
            let bar = max(unit * 0.14, lightInset * 2 + dot)
            let line = max(1.5, unit * 0.045)
            let showsSidebar = size.width > size.height * 0.9

            ZStack(alignment: .topLeading) {
                (isDark ? Color(white: 0.25) : Color.white)

                HStack(spacing: dot * 0.55) {
                    ForEach([Color(red: 1, green: 0.37, blue: 0.34),
                             Color(red: 1, green: 0.74, blue: 0.18),
                             Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { color in
                        Circle().fill(color).frame(width: dot, height: dot)
                    }
                }
                .padding(.leading, lightInset)
                .padding(.top, lightInset)

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
                    .foregroundStyle(isDark ? Color.white.opacity(0.9) : Color.black.opacity(0.75))
                    .position(
                        x: size.width * (pointer?.x ?? (showsSidebar ? 0.55 : 0.5)),
                        y: size.height * (pointer?.y ?? 0.66)
                    )
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

/// The camera: a person against a flat grey wall, cropped by the camera's
/// shape like a real webcam, in a thin white frame with a faint shadow.
private struct MiniatureCamera: View {
    let radius: CGFloat
    let isDark: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let head = min(size.width, size.height) * 0.36
            let headY = size.height * 0.5 - head * 0.12

            ZStack {
                isDark ? Color(white: 0.36) : Color(white: 0.82)
                Ellipse()
                    .fill(Color.white.opacity(isDark ? 0.75 : 0.92))
                    .frame(width: head * 2.15, height: head * 1.4)
                    .position(x: size.width / 2, y: headY + head * 1.28)
                Circle()
                    .fill(Color.white.opacity(isDark ? 0.85 : 1))
                    .frame(width: head, height: head)
                    .position(x: size.width / 2, y: headY)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isDark ? 0.3 : 0.95), lineWidth: 1.25)
            }
        }
        .shadow(color: .black.opacity(isDark ? 0.3 : 0.1), radius: 1.5, y: 0.5)
    }
}

/// The cutout: just the person, standing on the canvas's bottom edge with
/// the soft shadow the export gives them.
private struct MiniatureCutout: View {
    let isDark: Bool

    var body: some View {
        StudioPersonSilhouette()
            .fill(isDark ? Color(white: 0.56) : Color(white: 0.72))
            .shadow(color: .black.opacity(isDark ? 0.3 : 0.12), radius: 1.5, y: 0.5)
    }
}

/// Head and shoulders, centred in a camera picture's frame the way people
/// sit in front of a webcam; the frame's bottom edge crops the shoulders.
struct StudioPersonSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let head = rect.height * 0.4
        let headCenter = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.43)
        var path = Path()
        path.addEllipse(in: CGRect(
            x: headCenter.x - head / 2, y: headCenter.y - head / 2, width: head, height: head
        ))
        path.addEllipse(in: CGRect(
            x: headCenter.x - head * 1.15, y: headCenter.y + head * 0.6,
            width: head * 2.3, height: head * 1.4
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
