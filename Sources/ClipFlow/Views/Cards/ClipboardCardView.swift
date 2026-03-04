import SwiftUI
import ClipFlowCore
import ClipFlowBackend
import UniformTypeIdentifiers

struct ClipboardCardView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let viewModel: ClipboardViewModel
    private let contentTypeInfo: ContentTypeInfo

    @State private var cachedImagePath: String? = nil
    @State private var cachedNSImage: NSImage? = nil
    @State private var showCopyFeedback = false
    @State private var showTagMenu = false
    @State private var showNewTagCreator = false

    // PERFORMANCE: Cache computed tags instead of filtering on every render
    @State private var itemTags: [Tag] = []
    @State private var allTags: [Tag] = []

    // PERFORMANCE: Cache time-ago string — RelativeDateTimeFormatter + Date() is non-trivial
    @State private var cachedTimeAgo = ""

    // PERFORMANCE: Cache icon conversion - NSImage(data:) is EXPENSIVE!
    // This prevents 10-15 conversions per filter change
    @State private var cachedAppIcon: Image? = nil

    // PERFORMANCE: Cache metadata text — String.count is O(n) in Swift (Unicode traversal)
    @State private var cachedMetadata = ""

    init(item: ClipboardItem, index: Int, isSelected: Bool, viewModel: ClipboardViewModel) {
        self.item = item
        self.index = index
        self.isSelected = isSelected
        self.viewModel = viewModel
        self.contentTypeInfo = ContentTypeInfo.from(item.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header with type badge and index
            cardHeader

            // Tag indicators (if any tags)
            if !itemTags.isEmpty {
                tagIndicators
            }

            // Content preview
            contentPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Metadata footer
            cardFooter
        }
        .frame(width: cardWidth, height: 250)
        .containerShape(.rect(cornerRadius: 20))
        .glassEffect(
            isSelected
                ? .regular.tint(Color.accentColor.opacity(0.14)).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: 20)
        )
        .scaleEffect(showCopyFeedback ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: showCopyFeedback)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .overlay {
            // AppKit drag overlay for ALL card types.
            // SwiftUI .onDrag uses lazy NSItemProvider closures and does not fire
            // reliably from non-activating NSPanels. AppKit beginDraggingSession
            // works correctly from any panel, writes the pasteboard synchronously
            // (required by Chrome), and registers the UUID for tag-chip drops.
            AppKitCardDragOverlay(
                item: item,
                nsImage: cachedNSImage,
                fileURL: cachedImagePath.map { URL(fileURLWithPath: $0) }
            )
        }
        .onTapGesture(count: 2) {
            // Double-click to paste and hide overlay
            pasteAndHideOverlay()
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                copyItem()
            }
        )
        .contextMenu {
            cardContextMenu
        }
        .onAppear {
            // PERFORMANCE: Cache tags once on appear instead of computing every render
            allTags = TagService.shared.getAllTags()
            itemTags = allTags.filter { item.tagIds.contains($0.id) }

            // PERFORMANCE: Cache time-ago once — avoids formatter + Date() on every render
            cachedTimeAgo = Self.relativeDateFormatter.localizedString(
                for: item.timestamps.createdAt, relativeTo: Date())

            // PERFORMANCE: Cache metadata — String.count is O(n) for Unicode strings
            cachedMetadata = computeMetadataText()

            // PERFORMANCE: NSImage(data:) decodes TIFF with multiple resolutions — move off main thread
            if let iconData = item.source.applicationIcon {
                Task.detached(priority: .utility) {
                    let image = NSImage(data: iconData).map { Image(nsImage: $0) }
                    await MainActor.run { cachedAppIcon = image }
                }
            }

            // Decode NSImage and write temp file — both needed before the user drags.
            // .utility priority avoids saturating CPU threads when many image cards appear.
            if case .image(let imageContent) = item.content {
                Task.detached(priority: .utility) {
                    let imageData = imageContent.data
                    let nsImage = NSImage(data: imageData)
                    let tempPath = await createTemporaryImageFileAsync(from: imageContent)
                    await MainActor.run {
                        cachedNSImage = nsImage
                        if let tempPath { cachedImagePath = tempPath }
                    }
                }
            }
        }
    }

    private var cardWidth: CGFloat {
        return 235  // Uniform width for all card types
    }

    @Environment(\.colorScheme) private var colorScheme


    

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Content type badge — concentric corners match card radius
                Text(contentTypeInfo.name.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .rect(corners: .concentric(minimum: 4), isUniform: true))

                Spacer()

                // Source app icon badge
                appIconBadge
            }

        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var contentPreview: some View {
        Group {
            switch item.content {
            case .text(let textContent):
                TextPreviewCard(content: textContent)
            case .richText(let richTextContent):
                RichTextPreviewCard(content: richTextContent)
            case .image(let imageContent):
                ImagePreviewCard(content: imageContent)
            case .file(let fileContent):
                FilePreviewCard(content: fileContent)
            case .link(let linkContent):
                LinkPreviewCard(content: linkContent)
            case .code(let codeContent):
                TextPreviewCard(content: TextContent(plainText: codeContent.code))
            case .color(let colorContent):
                ColorPreviewCard(content: colorContent)
            case .snippet(let snippetContent):
                TextPreviewCard(content: TextContent(plainText: snippetContent.content))
            case .multiple(let multiContent):
                MultiPreviewCard(content: multiContent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var cardFooter: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Text(metadataText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(timeAgoText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var metadataText: String { cachedMetadata }

    private func computeMetadataText() -> String {
        switch item.content {
        case .text(let content):
            let count = content.plainText.count
            return count == 1 ? "1 character" : "\(count) characters"
        case .richText(let content):
            let count = content.plainTextFallback.count
            return count == 1 ? "1 character" : "\(count) characters"
        case .image(let content):
            return "\(content.format.rawValue.uppercased()) · \(Int(content.dimensions.width)) × \(Int(content.dimensions.height))"
        case .file(let content):
            return formatFileSize(content.fileSize)
        case .link:
            return "Link"
        case .code(let content):
            let count = content.code.count
            return count == 1 ? "1 character" : "\(count) characters"
        case .color:
            return "Color"
        case .snippet(let content):
            let count = content.content.count
            return count == 1 ? "1 character" : "\(count) characters"
        case .multiple(let content):
            return "\(content.items.count) items"
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var timeAgoText: String { cachedTimeAgo }
    
    

    private static let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()

    private func formatFileSize(_ bytes: Int64) -> String {
        Self.byteCountFormatter.string(fromByteCount: bytes)
    }

    // MARK: - Action Methods

    private func copyItem() {
        // Show subtle copy feedback animation
        withAnimation(.easeInOut(duration: 0.15)) {
            showCopyFeedback = true
        }

        // Reset feedback after animation
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeInOut(duration: 0.15)) {
                showCopyFeedback = false
            }
        }

        // Perform the paste
        viewModel.pasteItem(item)
    }

    private func pasteAndHideOverlay() {
        // CRITICAL: Hide overlay FIRST to restore focus to original text field
        NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)

        // Delay 250ms to ensure:
        // 1. Overlay hide animation completes (200ms)
        // 2. Focus restored to previous app/text field via NSWorkspace
        // 3. macOS processes focus change
        // 4. THEN paste into the now-focused text field
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            NSLog("📋 Double-click paste executing after overlay hidden and focus restored")

            // Add haptic feedback
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

            // NOW paste into restored text field
            self.viewModel.pasteItem(self.item)
        }
    }


    // MARK: - Drag and Drop Support

    private func createTemporaryImageFileAsync(from imageContent: ImageContent) async -> String? {
        return await Task(priority: .utility) {
            do {
                // Create temporary directory
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileName = "\(item.id.uuidString).\(imageContent.format.rawValue)"
                let tempURL = tempDir.appendingPathComponent(tempFileName)

                // Write image data to temporary file
                try imageContent.data.write(to: tempURL)

                return tempURL.path
            } catch {
                print("Failed to create temporary image file: \(error)")
                return nil
            }
        }.value
    }

    // MARK: - Source App Icon

    /// App icon badge view showing the source application
    /// PERFORMANCE: Uses cached icon to avoid repeated NSImage(data:) conversions
    private var appIconBadge: some View {
        Group {
            if let cachedIcon = cachedAppIcon {
                cachedIcon
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(.separator, lineWidth: 1.5)
                    )
            } else {
                Image(systemName: "app.badge")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
        }
    }

    // MARK: - Tag Indicators

    private var tagIndicators: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(itemTags.prefix(2)) { tag in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(tag.color.swiftUIColor)
                            .frame(width: 8, height: 8)

                        Text(tag.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: .rect(corners: .concentric(minimum: 8), isUniform: true))
                }

                if itemTags.count > 2 {
                    Text("+\(itemTags.count - 2)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Context Menu

    private var cardContextMenu: some View {
        Group {
            Button("Copy") {
                copyItem()
            }

            Button("Paste & Close") {
                pasteAndHideOverlay()
            }

            Divider()

            // Tag submenu
            Menu("Tag") {
                ForEach(allTags) { tag in
                    Button(action: {
                        toggleTag(tag)
                    }) {
                        HStack {
                            if itemTags.contains(where: { $0.id == tag.id }) {
                                Image(systemName: "checkmark")
                            }
                            Text(tag.name)
                            Spacer()
                            Circle()
                                .fill(tag.color.swiftUIColor)
                                .frame(width: 10, height: 10)
                        }
                    }
                }

                Divider()

                Button("New Tag...") {
                    showNewTagCreator = true
                }
            }
            .popover(isPresented: $showNewTagCreator) {
                VStack(spacing: 16) {
                    Text("Create New Tag")
                        .font(.headline)

                    InlineTagCreator { newTag in
                        // Add the newly created tag to this item
                        viewModel.addTagToItem(tagId: newTag.id, itemId: item.id)
                        itemTags.append(newTag)
                        allTags.append(newTag)
                        showNewTagCreator = false
                    }
                }
                .padding()
                .frame(width: 280)
            }

            Divider()

            Button("Delete", role: .destructive) {
                viewModel.deleteItem(item)
            }
        }
    }

    // MARK: - Tag Management

    private func toggleTag(_ tag: Tag) {
        if itemTags.contains(where: { $0.id == tag.id }) {
            viewModel.removeTagFromItem(tagId: tag.id, itemId: item.id)
            itemTags.removeAll { $0.id == tag.id }
        } else {
            viewModel.addTagToItem(tagId: tag.id, itemId: item.id)
            itemTags.append(tag)
        }
    }
}

// MARK: - AppKit Card Drag Overlay (all content types)

/// Transparent NSView overlay that drives AppKit drag sessions for all card types.
///
/// SwiftUI's `.onDrag` uses lazy NSItemProvider closures and does not reliably
/// fire from non-activating NSPanels — SwiftUI's drag gesture recogniser requires
/// normal application-activation event routing that panels deliberately bypass.
///
/// This overlay uses `beginDraggingSession(with:event:source:)` which works from
/// any NSView regardless of panel activation state, and writes all pasteboard data
/// SYNCHRONOUSLY via NSPasteboardItem — required by Chrome/Chromium which reads
/// pasteboard types at `draggingEntered:`, before any lazy closures run.
private struct AppKitCardDragOverlay: NSViewRepresentable {
    let item: ClipboardItem
    let nsImage: NSImage?   // Pre-decoded image; nil for non-image cards
    let fileURL: URL?        // Pre-written temp file; nil for non-image cards

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> CardDragView {
        let v = CardDragView()
        v.coordinator = context.coordinator
        return v
    }

    func updateNSView(_ v: CardDragView, context: Context) {
        context.coordinator.parent = self
    }

    // MARK: Coordinator — NSDraggingSource

    final class Coordinator: NSObject, NSDraggingSource {
        var parent: AppKitCardDragOverlay
        init(_ p: AppKitCardDragOverlay) { parent = p }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    }

    // MARK: Drag-capturing NSView

    final class CardDragView: NSView {
        var coordinator: Coordinator?
        private var mouseDownPoint: NSPoint = .zero
        private var dragStarted = false

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            dragStarted = false
            super.mouseDown(with: event)   // forward so SwiftUI tap gestures still fire
        }

        override func mouseDragged(with event: NSEvent) {
            guard !dragStarted, let coord = coordinator else {
                super.mouseDragged(with: event)
                return
            }
            let p = convert(event.locationInWindow, from: nil)
            guard hypot(p.x - mouseDownPoint.x, p.y - mouseDownPoint.y) > 4 else {
                super.mouseDragged(with: event)
                return
            }
            dragStarted = true

            let pbItem = buildPasteboardItem(for: coord.parent)
            let thumbnail = coord.parent.nsImage ?? blankThumbnail()

            let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
            dragItem.setDraggingFrame(CGRect(x: p.x - 60, y: p.y - 45, width: 120, height: 90),
                                      contents: thumbnail)
            beginDraggingSession(with: [dragItem], event: event, source: coord)
        }

        override func mouseUp(with event: NSEvent) {
            dragStarted = false
            super.mouseUp(with: event)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { self }
        override var acceptsFirstResponder: Bool { false }

        // MARK: Pasteboard Builder

        private func buildPasteboardItem(for overlay: AppKitCardDragOverlay) -> NSPasteboardItem {
            let pbItem = NSPasteboardItem()
            let item = overlay.item

            // UUID — ClipFlow's internal type checked by TagChipView.onDrop (always)
            if let data = item.id.uuidString.data(using: .utf8) {
                pbItem.setData(data, forType: NSPasteboard.PasteboardType(UTType.clipboardItemID.identifier))
            }

            // Content-specific data for paste into other apps
            switch item.content {
            case .image(_):
                // TIFF + legacy string — Chrome checks "NeXT TIFF v4.0 pasteboard type"
                if let tiffData = overlay.nsImage?.tiffRepresentation {
                    pbItem.setData(tiffData, forType: .tiff)
                    pbItem.setData(tiffData, forType: NSPasteboard.PasteboardType("NeXT TIFF v4.0 pasteboard type"))
                }
                // File URL + legacy filenames — Finder needs both
                if let url = overlay.fileURL {
                    pbItem.setString(url.absoluteString, forType: .fileURL)
                    pbItem.setPropertyList([url.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
                }
            case .text(let c):
                pbItem.setString(c.plainText, forType: .string)
            case .richText(let c):
                pbItem.setString(c.plainTextFallback, forType: .string)
            case .link(let c):
                let s = c.url.absoluteString
                pbItem.setString(s, forType: .string)
                pbItem.setString(s, forType: .URL)
            case .code(let c):
                pbItem.setString(c.code, forType: .string)
            case .color(let c):
                pbItem.setString(c.hexValue, forType: .string)
            case .snippet(let c):
                pbItem.setString(c.content, forType: .string)
            case .file(let c):
                if let url = c.urls.first {
                    pbItem.setString(url.absoluteString, forType: .fileURL)
                    pbItem.setPropertyList([url.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
                }
            case .multiple(let c):
                for subItem in c.items {
                    if case .text(let tc) = subItem {
                        pbItem.setString(tc.plainText, forType: .string)
                        break
                    }
                }
            }

            return pbItem
        }

        private func blankThumbnail() -> NSImage {
            NSImage(size: NSSize(width: 120, height: 90), flipped: false) { rect in
                NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
                return true
            }
        }
    }
}

#Preview("Card – Text") {
    let item = ClipboardItem(
        content: .text(TextContent(plainText: "func greet(_ name: String) -> String {\n    return \"Hello, \\(name)!\"\n}")),
        metadata: ItemMetadata.generate(for: .text(TextContent(plainText: "func greet..."))),
        source: ItemSource(applicationName: "Xcode")
    )
    let vm = ClipboardViewModel()
    return ClipboardCardView(item: item, index: 1, isSelected: true, viewModel: vm)
        .padding()
        .background(Color.gray.opacity(0.15))
}

#Preview("Card – Link") {
    let url = URL(string: "https://developer.apple.com/documentation/swiftui")!
    let linkContent = LinkContent(url: url, title: "SwiftUI Documentation")
    let item = ClipboardItem(
        content: .link(linkContent),
        metadata: ItemMetadata.generate(for: .link(linkContent)),
        source: ItemSource(applicationName: "Safari")
    )
    let vm = ClipboardViewModel()
    return ClipboardCardView(item: item, index: 2, isSelected: false, viewModel: vm)
        .padding()
        .background(Color.gray.opacity(0.15))
}

// Content type information for styling
struct ContentTypeInfo {
    let name: String
    let icon: String
    let color: Color

    static func from(_ content: ClipboardContent) -> ContentTypeInfo {
        switch content {
        case .text(let textContent):
            // Check if text is a hex color
            let text = textContent.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if isHexColor(text) {
                return ContentTypeInfo(name: "Color", icon: "paintpalette", color: .pink)
            }
            return ContentTypeInfo(name: "Text", icon: "doc.text", color: .blue)
        case .richText:
            return ContentTypeInfo(name: "Rich Text", icon: "doc.richtext", color: .blue)
        case .image:
            return ContentTypeInfo(name: "Image", icon: "photo", color: .green)
        case .file:
            return ContentTypeInfo(name: "File", icon: "doc", color: .orange)
        case .link:
            return ContentTypeInfo(name: "Link", icon: "link", color: .cyan)
        case .code:
            return ContentTypeInfo(name: "Code", icon: "chevron.left.forwardslash.chevron.right", color: .indigo)
        case .color:
            return ContentTypeInfo(name: "Color", icon: "paintpalette", color: .pink)
        case .snippet:
            return ContentTypeInfo(name: "Snippet", icon: "text.quote", color: .mint)
        case .multiple:
            return ContentTypeInfo(name: "Multiple", icon: "square.stack", color: .gray)
        }
    }

    private static func isHexColor(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), trimmed.count == 7 else { return false }

        let hexValue = String(trimmed.dropFirst())
        return Int(hexValue, radix: 16) != nil
    }
}

