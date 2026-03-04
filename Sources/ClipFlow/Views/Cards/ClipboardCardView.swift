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
        .onDrag {
            NSLog("🎯 DRAG: Starting drag for item: \(item.id.uuidString)")
            let provider = NSItemProvider()

            // FIRST: Register UUID with custom type for tag assignment
            // This is checked by TagChipView dropDestination
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.clipboardItemID.identifier,
                visibility: .all
            ) { completion in
                let data = self.item.id.uuidString.data(using: .utf8)!
                NSLog("🎯 DRAG: Registered UUID with custom type for tagging: \(self.item.id.uuidString)")
                completion(data, nil)
                return nil
            }

            // SECOND: Register actual content for drag-to-paste functionality
            switch item.content {
            case .image(_):
                // registerObject writes NSImage's type declarations to the drag
                // pasteboard EAGERLY at drag-start (not lazily at drop time).
                // Chrome checks available types at drag-enter; lazy closures aren't
                // populated yet so Chrome rejects the drop. Eager registration fixes this.
                if let nsImage = cachedNSImage {
                    provider.registerObject(nsImage, visibility: .all)
                }
                // Also provide the pre-cached file URL — Chrome needs a file:// URL
                // to open the image in a new tab or pass it to Gmail/Docs as a file.
                if let cachedPath = cachedImagePath {
                    let fileURL = URL(fileURLWithPath: cachedPath)
                    provider.registerFileRepresentation(
                        forTypeIdentifier: UTType.png.identifier,
                        fileOptions: [],
                        visibility: .all
                    ) { completion in
                        completion(fileURL, false, nil)
                        return Progress()
                    }
                }

            case .text(let textContent):
                // For text, provide string content
                if let data = textContent.plainText.data(using: .utf8) {
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.utf8PlainText.identifier,
                        visibility: .all
                    ) { completion in
                        completion(data, nil)
                        return nil
                    }
                    NSLog("🎯 DRAG: Registered text content (\(textContent.plainText.count) chars)")
                }

            case .richText(let richContent):
                // For rich text, provide plain text fallback
                if let data = richContent.plainTextFallback.data(using: .utf8) {
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.utf8PlainText.identifier,
                        visibility: .all
                    ) { completion in
                        completion(data, nil)
                        return nil
                    }
                    NSLog("🎯 DRAG: Registered rich text content")
                }

            case .file(let fileContent):
                // For files, provide file URLs
                for fileURL in fileContent.urls {
                    provider.registerFileRepresentation(
                        forTypeIdentifier: UTType.fileURL.identifier,
                        fileOptions: .openInPlace,
                        visibility: .all
                    ) { completion in
                        completion(fileURL, true, nil)
                        return Progress()
                    }
                }
                NSLog("🎯 DRAG: Registered \(fileContent.urls.count) file(s)")

            case .link(let linkContent):
                // For links, provide URL string
                if let data = linkContent.url.absoluteString.data(using: .utf8) {
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.url.identifier,
                        visibility: .all
                    ) { completion in
                        completion(data, nil)
                        return nil
                    }
                    NSLog("🎯 DRAG: Registered link URL")
                }

            case .code(let codeContent):
                // For code, provide string content
                if let data = codeContent.code.data(using: .utf8) {
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.utf8PlainText.identifier,
                        visibility: .all
                    ) { completion in
                        completion(data, nil)
                        return nil
                    }
                    NSLog("🎯 DRAG: Registered code content")
                }

            case .color(let colorContent):
                // For colors, provide hex string
                if let data = colorContent.hexValue.data(using: .utf8) {
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.utf8PlainText.identifier,
                        visibility: .all
                    ) { completion in
                        completion(data, nil)
                        return nil
                    }
                    NSLog("🎯 DRAG: Registered color hex value")
                }

            case .snippet(let snippetContent):
                // For snippets, provide string content
                if let data = snippetContent.content.data(using: .utf8) {
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.utf8PlainText.identifier,
                        visibility: .all
                    ) { completion in
                        completion(data, nil)
                        return nil
                    }
                    NSLog("🎯 DRAG: Registered snippet content")
                }

            case .multiple(let multiContent):
                // For multiple items, provide the first text-like content
                for subItem in multiContent.items {
                    if case .text(let textContent) = subItem,
                       let data = textContent.plainText.data(using: .utf8) {
                        provider.registerDataRepresentation(
                            forTypeIdentifier: UTType.utf8PlainText.identifier,
                            visibility: .all
                        ) { completion in
                            completion(data, nil)
                            return nil
                        }
                        NSLog("🎯 DRAG: Registered multi-item content")
                        break
                    }
                }
            }

            // Note: We no longer register UUID as plainText since we have custom UTType
            // This prevents UUID from interfering with paste operations
            return provider
        }
        .overlay {
            // AppKit drag overlay for images: NSDraggingItem writes to the drag
            // pasteboard SYNCHRONOUSLY, so Chrome sees data at drag-enter.
            // SwiftUI .onDrag uses lazy NSItemProvider closures — Chrome checks
            // types before data is available and rejects the drop.
            if case .image = item.content {
                AppKitImageDragOverlay(
                    nsImage: cachedNSImage,
                    fileURL: cachedImagePath.map { URL(fileURLWithPath: $0) },
                    itemID: item.id
                )
            }
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

    private var metadataText: String {
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

// MARK: - AppKit Image Drag Overlay

/// Transparent NSView overlay that drives AppKit drag sessions for image cards.
///
/// Chrome (and other Chromium-based apps) reads NSPasteboard contents
/// synchronously at `draggingEntered:`. SwiftUI's `.onDrag` uses lazy
/// NSItemProvider closures — the data isn't populated until drop time, so Chrome
/// never sees it and rejects the drop. `NSDraggingItem(pasteboardWriter: NSImage)`
/// writes to the pasteboard *synchronously* at drag-start, including
/// "NeXT TIFF v4.0 pasteboard type" which Chrome specifically checks for.
private struct AppKitImageDragOverlay: NSViewRepresentable {
    let nsImage: NSImage?
    let fileURL: URL?
    let itemID: UUID

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ImageDragView {
        let v = ImageDragView()
        v.coordinator = context.coordinator
        return v
    }

    func updateNSView(_ v: ImageDragView, context: Context) {
        context.coordinator.parent = self
    }

    // MARK: Coordinator — NSDraggingSource

    final class Coordinator: NSObject, NSDraggingSource {
        var parent: AppKitImageDragOverlay
        init(_ p: AppKitImageDragOverlay) { parent = p }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    }

    // MARK: Drag-capturing NSView

    final class ImageDragView: NSView {
        var coordinator: Coordinator?
        private var mouseDownPoint: NSPoint = .zero
        private var dragStarted = false

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            dragStarted = false
            super.mouseDown(with: event)   // forward so SwiftUI tap gestures still work
        }

        override func mouseDragged(with event: NSEvent) {
            guard !dragStarted,
                  let coord = coordinator,
                  let img = coord.parent.nsImage else {
                super.mouseDragged(with: event)
                return
            }
            let p = convert(event.locationInWindow, from: nil)
            guard hypot(p.x - mouseDownPoint.x, p.y - mouseDownPoint.y) > 4 else {
                super.mouseDragged(with: event)
                return
            }
            dragStarted = true

            // ONE NSPasteboardItem with all types — single drag thumbnail, no stacking.
            let pbItem = NSPasteboardItem()

            // TIFF (modern UTType + legacy string) — Chrome checks "NeXT TIFF v4.0 pasteboard type"
            if let tiffData = img.tiffRepresentation {
                pbItem.setData(tiffData, forType: .tiff)
                pbItem.setData(tiffData, forType: NSPasteboard.PasteboardType("NeXT TIFF v4.0 pasteboard type"))
            }

            // File URL + legacy filenames — Finder needs both to accept a file drop
            if let url = coord.parent.fileURL {
                pbItem.setString(url.absoluteString, forType: .fileURL)
                pbItem.setPropertyList([url.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
            }

            // UUID — ClipFlow's internal tag-assignment type
            if let data = coord.parent.itemID.uuidString.data(using: .utf8) {
                pbItem.setData(data, forType: NSPasteboard.PasteboardType(UTType.clipboardItemID.identifier))
            }

            let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
            dragItem.setDraggingFrame(CGRect(x: p.x - 60, y: p.y - 45, width: 120, height: 90),
                                      contents: img)

            beginDraggingSession(with: [dragItem], event: event, source: coord)
        }

        override func mouseUp(with event: NSEvent) {
            dragStarted = false
            super.mouseUp(with: event)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { self }
        override var acceptsFirstResponder: Bool { false }
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

