import SwiftUI
import AppKit
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
    @State private var showRenameSheet = false
    @State private var renameText = ""
    @State private var editWindow: NSWindow? = nil
    @State private var previewWindow: NSWindow? = nil
    @State private var tagTintColor: Color = .clear

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

    // Drag thumbnail: full card rendered via ImageRenderer, used as NSDraggingItem preview
    @State private var dragThumbnail: NSImage? = nil

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
            tagTintColor == .clear
                ? .regular.interactive()
                : .regular.tint(tagTintColor.opacity(0.1)).interactive(),
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
                fileURL: cachedImagePath.map { URL(fileURLWithPath: $0) },
                dragThumbnail: dragThumbnail
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
        .sheet(isPresented: $showRenameSheet) {
            renameSheet
        }
        .onAppear {
            // PERFORMANCE: Cache tags once on appear instead of computing every render
            allTags = TagService.shared.getAllTags()
            itemTags = allTags.filter { item.tagIds.contains($0.id) }
            // Apply first tag's color as a subtle card tint
            tagTintColor = itemTags.first.map { $0.color.swiftUIColor } ?? .clear

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

            // Build initial drag thumbnail (image cards show placeholder until decode below)
            buildDragThumbnail()

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
                        // Re-render thumbnail now that the image is decoded
                        buildDragThumbnail()
                    }
                }
            }
        }
    }

    private var cardWidth: CGFloat {
        return 235  // Uniform width for all card types
    }

    @Environment(\.colorScheme) private var colorScheme

    /// Renders the full card as a bitmap via ImageRenderer (main thread only).
    /// Called on appear and re-called after image decode for image cards.
    private func buildDragThumbnail() {
        let preview = DragPreviewCard(item: item, nsImage: cachedNSImage)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: preview)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        dragThumbnail = renderer.nsImage
    }


    

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Badge shows custom name when set, otherwise content type
                let badgeLabel = viewModel.customName(for: item.id)?.uppercased()
                    ?? contentTypeInfo.name.uppercased()
                Text(badgeLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: .rect(corners: .concentric(minimum: 4), isUniform: true))

                // Pin indicator
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(45))
                }

                Spacer()

                // Source app icon badge
                appIconBadge
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Divider()
        }
        .background(Color.primary.opacity(0.04))
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
                    .frame(width: 36, height: 36)
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
            // Paste to frontmost app (dynamic label — panel is non-activating so frontmost = previous app)
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "App"
            Button("Paste to \(frontApp)") {
                pasteAndHideOverlay()
            }

            Button("Paste as Plain Text") {
                NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    viewModel.pasteItem(item, transform: .removeFormatting)
                }
            }

            Button("Copy") {
                viewModel.copyToClipboard(item)
            }

            Divider()

            // Edit — only for text-type items
            if case .text = item.content {
                Button("Edit") {
                    openEditWindow()
                }
            }

            Button("Rename") {
                renameText = viewModel.customName(for: item.id) ?? ""
                showRenameSheet = true
            }

            Divider()

            // Pin submenu
            Menu("Pin") {
                if item.isPinned {
                    Button("Unpin") { viewModel.setPinned(false, for: item) }
                } else {
                    Button("Pin to Top") { viewModel.setPinned(true, for: item) }
                }
            }

            Button("Preview") {
                openPreviewWindow()
            }

            Button("Share...") {
                shareItem()
            }

            Divider()

            // Tag submenu
            Menu("Tag") {
                ForEach(allTags) { tag in
                    Button(action: { toggleTag(tag) }) {
                        HStack {
                            if itemTags.contains(where: { $0.id == tag.id }) {
                                Image(systemName: "checkmark")
                            }
                            Text(tag.name)
                        }
                    }
                }
                Divider()
                Button("New Tag...") { showNewTagCreator = true }
            }
            .popover(isPresented: $showNewTagCreator) {
                VStack(spacing: 16) {
                    Text("Create New Tag").font(.headline)
                    InlineTagCreator { newTag in
                        viewModel.addTagToItem(tagId: newTag.id, itemId: item.id)
                        itemTags.append(newTag)
                        allTags.append(newTag)
                        tagTintColor = newTag.color.swiftUIColor
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

    // MARK: - Centered Windows (Edit / Preview)

    private func openEditWindow() {
        guard case .text(let c) = item.content else { return }
        editWindow?.close()
        let capturedItem = item
        let view = EditWindowView(text: c.plainText) { savedText in
            viewModel.updateItemText(capturedItem, newText: savedText)
            editWindow?.close()
            editWindow = nil
        } onCancel: {
            editWindow?.close()
            editWindow = nil
        }
        let controller = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: controller)
        win.title = "Edit Item"
        win.styleMask = NSWindow.StyleMask([.titled, .closable])
        win.setContentSize(NSSize(width: 560, height: 380))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        editWindow = win
    }

    private func openPreviewWindow() {
        previewWindow?.close()
        let capturedItem = item
        let capturedVM = viewModel
        let title = viewModel.customName(for: item.id) ?? contentTypeInfo.name
        let view = PreviewWindowView(item: capturedItem, viewModel: capturedVM) {
            previewWindow?.close()
            previewWindow = nil
        }
        let controller = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: controller)
        win.title = title
        win.styleMask = NSWindow.StyleMask([.titled, .closable, .resizable])
        win.setContentSize(NSSize(width: 620, height: 520))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = win
    }

    // MARK: - Rename Sheet

    private var renameSheet: some View {
        VStack(spacing: 16) {
            Text("Rename Item")
                .font(.headline)

            TextField("Custom name (optional)", text: $renameText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Clear") {
                    viewModel.setCustomName(nil, for: item.id)
                    showRenameSheet = false
                }
                Spacer()
                Button("Cancel") { showRenameSheet = false }
                    .buttonStyle(.bordered)
                Button("Save") {
                    viewModel.setCustomName(renameText, for: item.id)
                    showRenameSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    // MARK: - Share

    private func shareItem() {
        var shareItems: [Any] = []
        switch item.content {
        case .text(let c):     shareItems = [c.plainText]
        case .richText(let c): shareItems = [c.plainTextFallback]
        case .link(let c):     shareItems = [c.url]
        case .code(let c):     shareItems = [c.code]
        case .color(let c):    shareItems = [c.hexValue]
        case .snippet(let c):  shareItems = [c.content]
        case .image(let c):
            if let img = NSImage(data: c.data) { shareItems = [img] }
        case .file(let c):     shareItems = c.urls
        case .multiple(let c):
            for sub in c.items {
                if case .text(let t) = sub { shareItems = [t.plainText]; break }
            }
        }
        guard !shareItems.isEmpty else { return }
        let picker = NSSharingServicePicker(items: shareItems)
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
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

// MARK: - Edit Window View

private struct EditWindowView: View {
    @State var text: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Item").font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                Button("Save") { onSave(text) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()

            Divider()

            TextEditor(text: $text)
                .font(.system(size: 13))
                .padding(12)
        }
        .frame(width: 560, height: 380)
    }
}

// MARK: - Preview Window View

private struct PreviewWindowView: View {
    let item: ClipboardItem
    let viewModel: ClipboardViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.customName(for: item.id) ?? item.content.typeDisplayName)
                    .font(.headline)
                Spacer()
                Button("Done") { onClose() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            DetailView(item: item, viewModel: viewModel)
        }
        .frame(width: 620, height: 520)
    }
}

// MARK: - Drag Preview Card

/// Synchronous card replica used as the NSDraggingItem thumbnail.
/// Rendered via ImageRenderer (no window required) so it uses solid fills
/// instead of .glassEffect — glass requires a live compositor backdrop.
private struct DragPreviewCard: View {
    let item: ClipboardItem
    let nsImage: NSImage?   // Decoded image for image cards; nil otherwise

    private static let cardW: CGFloat = 235
    private static let cardH: CGFloat = 250
    private var info: ContentTypeInfo { ContentTypeInfo.from(item.content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(info.name.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .rect(cornerRadius: 4))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Content
            previewContent
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer
            Divider()
            HStack {
                Text(footerText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: Self.cardW, height: Self.cardH)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.content {
        case .text(let c):
            Text(c.plainText)
                .font(.system(size: 13))
                .lineLimit(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .richText(let c):
            Text(c.plainTextFallback)
                .font(.system(size: 13))
                .lineLimit(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .image(_):
            Group {
                if let img = nsImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Color.secondary.opacity(0.15)
                        .overlay(Image(systemName: "photo").font(.system(size: 24)).foregroundStyle(.secondary))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 8)
        case .link(let c):
            VStack(alignment: .leading, spacing: 6) {
                if let title = c.title, !title.isEmpty {
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(5)
                } else {
                    Text(c.url.absoluteString).font(.system(size: 13)).lineLimit(6)
                }
                if let host = c.url.host {
                    Text(host).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .code(let c):
            Text(c.code)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .color(let c):
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha))
                .overlay(
                    Text(c.hexValue.uppercased())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) > 0.5
                                ? Color.black : Color.white
                        )
                )
                .padding(.bottom, 8)
        case .file(let c):
            VStack(alignment: .leading, spacing: 6) {
                Text(c.fileName).font(.system(size: 13, weight: .medium)).lineLimit(4)
                Text(c.fileType.uppercased()).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .snippet(let c):
            Text(c.content)
                .font(.system(size: 13))
                .lineLimit(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .multiple(let c):
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 20))
                Text("\(c.items.count) Items").font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var footerText: String {
        switch item.content {
        case .text(let c): return "\(c.plainText.count) chars"
        case .richText(let c): return "\(c.plainTextFallback.count) chars"
        case .image(let c): return "\(c.format.rawValue.uppercased())"
        case .file(let c): return c.fileName
        case .link: return "Link"
        case .code(let c): return "\(c.code.count) chars"
        case .color: return "Color"
        case .snippet(let c): return "\(c.content.count) chars"
        case .multiple(let c): return "\(c.items.count) items"
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
    let nsImage: NSImage?       // Pre-decoded image; nil for non-image cards
    let fileURL: URL?           // Pre-written temp file; nil for non-image cards
    let dragThumbnail: NSImage? // Full card snapshot via ImageRenderer

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> CardDragView {
        let v = CardDragView()
        v.coordinator = context.coordinator
        v.autoresizingMask = [.width, .height]
        return v
    }

    func updateNSView(_ v: CardDragView, context: Context) {
        context.coordinator.parent = self
        // Guarantee drag view is the frontmost sibling in AppKit's hit-test order.
        // glassEffect may insert NSGlassEffectView siblings after our view is created,
        // shadowing it for certain content regions (notably decoded image areas).
        v.bringToFront()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CardDragView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 235, height: proposal.height ?? 250)
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

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            guard let sv = superview else { return }
            frame = sv.bounds
            autoresizingMask = [.width, .height]
            // Move to front so we win AppKit hit-test against any glass effect siblings
            bringToFront()
        }

        override func layout() {
            super.layout()
            // Keep frame in sync after any SwiftUI layout pass that resizes our container
            guard let sv = superview, frame != sv.bounds else { return }
            frame = sv.bounds
        }

        /// Moves this view to the end of the superview's subview list,
        /// making it the frontmost view in AppKit's hit-test traversal.
        func bringToFront() {
            guard let sv = superview, sv.subviews.last !== self else { return }
            sv.sortSubviews({ v1, v2, _ in
                v1 is CardDragView ? .orderedDescending : .orderedSame
            }, context: nil)
        }

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
            // Use the pre-rendered full-card thumbnail; fall back to image or blank
            let thumbnail = coord.parent.dragThumbnail
                ?? coord.parent.nsImage
                ?? blankThumbnail()

            // Size matches the actual card; offset so the click point stays under cursor
            let cardW: CGFloat = 235
            let cardH: CGFloat = 250
            let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
            dragItem.setDraggingFrame(
                CGRect(x: p.x - mouseDownPoint.x,
                       y: p.y - mouseDownPoint.y,
                       width: cardW, height: cardH),
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

