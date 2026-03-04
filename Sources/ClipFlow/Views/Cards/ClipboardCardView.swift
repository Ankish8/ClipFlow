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
    @State private var showCopyFeedback = false
    @State private var showTagMenu = false
    @State private var showNewTagCreator = false

    // PERFORMANCE: Cache computed tags instead of filtering on every render
    @State private var itemTags: [Tag] = []
    @State private var allTags: [Tag] = []

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
        .background { cardBackground }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isSelected ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
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
                // For images, provide the pre-cached temporary file
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
                    NSLog("🎯 DRAG: Registered image file: \(fileURL.lastPathComponent)")
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

            // PERFORMANCE: NSImage(data:) decodes TIFF with multiple resolutions — move off main thread
            if let iconData = item.source.applicationIcon {
                Task.detached(priority: .utility) {
                    let image = NSImage(data: iconData).map { Image(nsImage: $0) }
                    await MainActor.run { cachedAppIcon = image }
                }
            }

            // Create temporary file for images asynchronously to avoid blocking main thread during drag
            if case .image(let imageContent) = item.content {
                Task.detached(priority: .utility) {
                    if let tempPath = await createTemporaryImageFileAsync(from: imageContent) {
                        await MainActor.run {
                            cachedImagePath = tempPath
                        }
                    }
                }
            }
        }
    }

    private var cardWidth: CGFloat {
        return 235  // Uniform width for all card types
    }

    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(isSelected ? Color.customAccent.opacity(0.14) : Color.primary.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Subtle content type badge
                Text(contentTypeInfo.name.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.12))
                    )

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
            // Exact divider from HTML reference
            Rectangle()
                .fill(colorScheme == .light ?
                    Color(.sRGB, red: 0.886, green: 0.91, blue: 0.941, opacity: 0.5) : // rgba(226, 232, 240, 0.5)
                    Color(.sRGB, red: 0.4, green: 0.4, blue: 0.4, opacity: 0.3)
                )
                .frame(height: 1)

            HStack {
                // Metadata - exact colors from HTML reference
                Text(metadataText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(colorScheme == .light ?
                        Color(.sRGB, red: 0.581, green: 0.639, blue: 0.722, opacity: 1.0) : // #94a3b8
                        Color(.sRGB, red: 0.7, green: 0.7, blue: 0.7, opacity: 1.0)
                    )

                Spacer()

                // Timestamp - exact colors from HTML reference
                Text(timeAgoText)
                    .font(.system(size: 11))
                    .foregroundStyle(colorScheme == .light ?
                        Color(.sRGB, red: 0.581, green: 0.639, blue: 0.722, opacity: 1.0) : // #94a3b8
                        Color(.sRGB, red: 0.7, green: 0.7, blue: 0.7, opacity: 1.0)
                    )
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

    private var timeAgoText: String {
        Self.relativeDateFormatter.localizedString(for: item.timestamps.createdAt, relativeTo: Date())
    }
    
    

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
                // Use cached icon - FAST!
                cachedIcon
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(colorScheme == .light ?
                                Color.white.opacity(0.8) :
                                Color.black.opacity(0.4),
                                lineWidth: 1.5
                            )
                    )
            } else {
                // Fallback to SF Symbol if no icon cached
                Image(systemName: "app.badge")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colorScheme == .light ?
                        Color(.sRGB, red: 0.581, green: 0.639, blue: 0.722, opacity: 1.0) :
                        Color(.sRGB, red: 0.7, green: 0.7, blue: 0.7, opacity: 1.0)
                    )
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
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                            )

                        Text(tag.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(tag.color.swiftUIColor.opacity(0.15))
                    )
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

