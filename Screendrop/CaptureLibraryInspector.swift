import AppKit
import SwiftUI

/// The Library's inspector: a large preview of the selection, its details,
/// and a footer of actions built like the editors' footers - one prominent
/// capsule for the main action, glass buttons for the rest.
struct CaptureLibraryInspector: View {
    let model: CaptureLibraryModel
    @State private var byteCount: Int64?
    @State private var pendingCloudDelete: CaptureLibraryItem?
    @State private var pendingCloudUpload: CaptureLibraryItem?
    @State private var similar: [CaptureLibraryItem] = []
    @Namespace private var glass
    private var items: [CaptureLibraryItem] { model.selectedItems }
    private var index: CaptureLibraryIndex { .shared }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyStateView(
                    systemImage: "photo.on.rectangle.angled",
                    title: "No Selection",
                    message: "Select a screenshot or recording to see its details."
                )
                .transition(.opacity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if items.count == 1, let item = items.first {
                            header(item)
                            InspectorGroupBreak()
                            information(item)
                            recognizedText(item)
                            similarCaptures(item)
                        } else {
                            multipleSelection
                        }
                    }
                    .padding(.top, InspectorMetrics.horizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollEdgeEffectSoftIfAvailable()
                .transition(.opacity)
            }
        }
        // A bar rather than an inset, so the scroll view's soft edge fades
        // the list out under the buttons instead of showing it through them.
        .safeAreaBarIfAvailable(edge: .bottom) {
            if !items.isEmpty {
                actionFooter
                    .transition(.rise)
            }
        }
        .motion(.morph, value: items.isEmpty)
        .onChange(of: items.map(\.id)) { _, _ in
            pendingCloudUpload = nil
        }
        .task(id: similarityKey) {
            guard items.count == 1, let item = items.first else { similar = []; return }
            let ids = await index.similar(to: item.id, among: model.items.map(\.id), limit: 9)
            guard !Task.isCancelled else { return }
            similar = ids.compactMap(model.item(id:))
        }
        .task(id: items.map(\.thumbnailKey)) {
            byteCount = nil
            let urls = items.map(\.ownedURL)
            let scan = Task.detached(priority: .utility) {
                urls.reduce(Int64(0)) { total, url in
                    Task.isCancelled ? total : total + CaptureLibraryScanner.sizeOnDisk(of: url)
                }
            }
            let size = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
            guard !Task.isCancelled else { return }
            byteCount = size
        }
        .alert("Delete from cloud?", isPresented: Binding(
            get: { pendingCloudDelete != nil }, set: { if !$0 { pendingCloudDelete = nil } }
        ), presenting: pendingCloudDelete) { item in
            Button("Delete", role: .destructive) {
                model.deleteCloudCopy(item)
                pendingCloudDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingCloudDelete = nil }
        } message: { _ in
            Text("This permanently removes the cloud copy and breaks its share link. Your local capture stays in the Library.")
        }
    }

    // MARK: Header

    private func header(_ item: CaptureLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Button { model.perform(.preview) } label: {
                CaptureLibraryThumbnail(item: item)
                    .aspectRatio(1.45, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
                    .hairline(radius: Radius.card)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: item.isVideo ? "play.fill" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.label)
                            .frame(width: 28, height: 28)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .padding(Space.m)
                    }
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .accessibilityLabel("Quick Look \(item.name)")
            .help("Quick Look (Space)")

            VStack(alignment: .leading, spacing: Space.s) {
                Text(item.name)
                    .font(.dsTitle)
                    .foregroundStyle(Palette.label)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let title = index.analyses[item.id]?.title {
                    Text(title)
                        .font(.dsCaption)
                        .foregroundStyle(Palette.secondaryLabel)
                        .lineLimit(2)
                        .help("Described on this Mac by Apple Intelligence")
                }
                HStack(spacing: Space.s) {
                    Tag(text: item.kindTitle, systemImage: item.isVideo ? "film" : "photo")
                    if let category = index.analyses[item.id]?.category, category != .other {
                        Tag(text: category.title, systemImage: category.symbol)
                    }
                    if item.hasDraft {
                        Tag(text: "Unsaved Edits", systemImage: "circle.lefthalf.filled", tint: Palette.warning)
                    } else if item.hasEdits {
                        Tag(text: "Edited", systemImage: "slider.horizontal.3")
                    }
                    if item.cloudURL != nil {
                        Tag(text: "Shared", systemImage: "link")
                    }
                }
            }
        }
        .padding(.horizontal, InspectorMetrics.horizontalPadding)
    }

    private func information(_ item: CaptureLibraryItem) -> some View {
        InspectorSection("Information") {
            VStack(spacing: InspectorMetrics.rowSpacing) {
                if let source = item.source {
                    sourceRow(source)
                }
                detailRow("Dimensions", value: item.dimensions)
                if item.isVideo { detailRow("Duration", value: item.durationText) }
                detailRow("Size on disk", value: sizeText)
                detailRow("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                detailRow("Modified", value: item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func sourceRow(_ source: CaptureSource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("App")
                .font(.inspectorLabel)
                .foregroundStyle(Palette.secondaryLabel)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Button {
                    model.searchText = ""
                    model.scope = .app(source.appKey)
                } label: {
                    HStack(spacing: 5) {
                        Image(nsImage: LibraryAppIcons.icon(for: source.bundleIdentifier))
                            .resizable()
                            .frame(width: 14, height: 14)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                        Text(source.appName)
                            .font(.inspectorValue)
                            .foregroundStyle(Palette.label)
                    }
                }
                .buttonStyle(.plain)
                .help("Show all captures from \(source.appName)")
                if let window = source.windowTitle {
                    Text(window)
                        .font(.dsCaption)
                        .foregroundStyle(Palette.secondaryLabel)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// The text Vision read in the capture, to read or copy without opening it.
    @ViewBuilder
    private func recognizedText(_ item: CaptureLibraryItem) -> some View {
        if let analysis = index.analyses[item.id], analysis.version == CaptureAnalysis.currentVersion {
            let text = analysis.text
            if !text.isEmpty {
                InspectorSection("Text") {
                    InspectorIconButton(systemName: "doc.on.doc", help: "Copy Text") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                } content: {
                    Text(text)
                        .font(.dsCaption)
                        .foregroundStyle(Palette.label)
                        .lineLimit(14)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        } else if index.pendingCount > 0 {
            InspectorSection("Text") {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.mini)
                    Text("Reading text…")
                        .font(.dsCaption)
                        .foregroundStyle(Palette.secondaryLabel)
                }
            }
        }
    }

    /// Captures that look alike, by Vision feature print. Choosing one
    /// selects it in the browser, widening the view if it's filtered out.
    @ViewBuilder
    private func similarCaptures(_ item: CaptureLibraryItem) -> some View {
        if !similar.isEmpty {
            InspectorSection("Similar") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.m), count: 3), spacing: Space.m) {
                    ForEach(similar) { match in
                        Button { model.reveal(match.id) } label: {
                            CaptureLibraryThumbnail(item: match)
                                .aspectRatio(1.3, contentMode: .fit)
                                .clipShape(.rect(cornerRadius: Radius.tile, style: .continuous))
                                .hairline(radius: Radius.tile, opacity: 0.08)
                        }
                        .buttonStyle(.plain)
                        .help(match.name)
                        .accessibilityLabel("Select \(match.name)")
                    }
                }
            }
        }
    }

    private var similarityKey: String {
        guard items.count == 1, let item = items.first else { return "" }
        return "\(item.id)|\(index.analyses[item.id]?.hasFeaturePrint == true)|\(model.items.count)"
    }

    private var multipleSelection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.l) {
                // A loose fan of the first few, so a multi-selection reads
                // as a stack of captures rather than a list.
                ZStack {
                    ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                        CaptureLibraryThumbnail(item: item)
                            .aspectRatio(1.45, contentMode: .fit)
                            .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
                            .hairline(radius: Radius.card)
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                            .scaleEffect(1 - CGFloat(index) * 0.06)
                            .rotationEffect(.degrees(Double(index) * (index.isMultiple(of: 2) ? 3.5 : -3.5)))
                            .offset(y: -CGFloat(index) * 8)
                    }
                }
                .padding(.top, Space.l)
                .padding(.horizontal, Space.m)
                .motion(value: items.count)

                Text("\(items.count) Captures")
                    .font(.dsTitle)
                    .foregroundStyle(Palette.label)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, InspectorMetrics.horizontalPadding)

            InspectorGroupBreak()

            InspectorSection("Selection") {
                VStack(spacing: InspectorMetrics.rowSpacing) {
                    detailRow("Screenshots", value: "\(items.filter { !$0.isVideo }.count)")
                    detailRow("Recordings", value: "\(items.filter(\.isVideo).count)")
                    detailRow("Size on disk", value: sizeText)
                }
            }
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.inspectorLabel)
                .foregroundStyle(Palette.secondaryLabel)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            Text(value)
                .font(.inspectorValue)
                .foregroundStyle(Palette.label)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .contentTransition(.numericText())
        }
    }

    private var sizeText: String {
        byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Calculating…"
    }

    // MARK: Footer

    private var actionFooter: some View {
        let single = items.count == 1 ? items.first : nil
        return GlassEffectContainer(spacing: GlassMetrics.containerSpacing) {
            HStack(spacing: GlassMetrics.gap) {
                GlassActionCapsule(
                    title: single?.isVideo == true ? "Edit" : "Annotate",
                    systemImage: single?.isVideo == true ? "film" : "pencil.tip.crop.circle",
                    isProminent: true
                ) {
                    model.perform(.edit)
                }
                .disabled(single == nil)
                .glassEffectID("edit", in: glass)

                GlassConfirmButton(
                    systemImage: "doc.on.doc",
                    help: "Copy (⌘C)",
                    size: GlassMetrics.actionHeight
                ) {
                    model.perform(.copy)
                }
                .glassEffectID("copy", in: glass)

                if CloudUploader.shared.isConfigured || items.contains(where: { $0.cloudURL != nil }) {
                    cloudButton(single)
                        .glassEffectID("cloud", in: glass)
                }

                moreMenu(single)
                    .glassEffectID("more", in: glass)
            }
        }
        .padding(.horizontal, InspectorMetrics.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .disabled(model.isBusy)
    }

    @ViewBuilder
    private func cloudButton(_ item: CaptureLibraryItem?) -> some View {
        if let item, item.cloudURL != nil {
            GlassConfirmButton(
                systemImage: "link",
                help: "Copy Cloud Link",
                size: GlassMetrics.actionHeight
            ) {
                model.copyLink(item)
            }
        } else {
            GlassIconButton(
                systemImage: "icloud.and.arrow.up",
                help: "Share to Cloud",
                size: GlassMetrics.actionHeight
            ) {
                pendingCloudUpload = item
            }
            .disabled(item == nil)
            .popover(item: $pendingCloudUpload, arrowEdge: .top) { item in
                CloudUploadOptionsPopover(suggestedTitle: item.name) { options in
                    model.upload(item, options: options)
                }
            }
        }
    }

    private func moreMenu(_ item: CaptureLibraryItem?) -> some View {
        Menu {
            Button("Export…", systemImage: "square.and.arrow.up") { model.perform(.export) }
            if item != nil {
                Button("Rename…", systemImage: "pencil") { model.perform(.rename) }
            }
            Button("Reveal in Finder", systemImage: "folder") { model.perform(.reveal) }
            if let item, let link = item.cloudURL {
                Divider()
                if let url = URL(string: link) {
                    Link(destination: url) { Label("Open Shared Capture", systemImage: "arrow.up.right") }
                }
                Button("Delete from Cloud…", systemImage: "icloud.slash", role: .destructive) {
                    pendingCloudDelete = item
                }
            }
            Divider()
            Button("Move to Trash…", systemImage: "trash", role: .destructive) { model.perform(.trash) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: GlassMetrics.symbolSize, weight: .semibold))
                .foregroundStyle(Palette.label)
                .frame(width: GlassMetrics.actionHeight, height: GlassMetrics.actionHeight)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .circle)
        .help("More Actions")
        .accessibilityLabel("More capture actions")
    }
}
