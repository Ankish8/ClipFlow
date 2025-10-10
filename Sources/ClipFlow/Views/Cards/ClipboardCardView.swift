import SwiftUI
import ClipFlowCore
import ClipFlowBackend
import UniformTypeIdentifiers

struct ClipboardCardView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let viewModel: ClipboardViewModel
    @State private var cachedImagePath: String? = nil
    @State private var showCopyFeedback = false
    @State private var accentColor: Color? = nil
    @State private var itemTags: [Tag] = []
    @State private var allTags: [Tag] = []
    @State private var showTagMenu = false
    @State private var showNewTagCreator = false

    private var contentTypeInfo: ContentTypeInfo {
        ContentTypeInfo.from(item.content)
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
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    // Alternative drag gesture for traditional drag-and-drop
                }
        )
        .onTapGesture(count: 2) {
            // Double-click to paste and hide overlay
            pasteAndHideOverlay()
        }
        .onTapGesture {
            // Single-click to copy
            copyItem()
        }
        .contextMenu {
            cardContextMenu
        }
        .onAppear {
            loadTags()
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

            // Extract dominant color from app icon for card theming
            Task {
                await extractAccentColor()
            }
        }
    }

    private var cardWidth: CGFloat {
        return 235  // Uniform width for all card types
    }

    @Environment(\.colorScheme) var colorScheme

    private var cardBackground: some View {
        ZStack {
            // Strong card background like Paste app
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .light ?
                    Color(.sRGB, red: 1.0, green: 1.0, blue: 1.0, opacity: 0.95) : // Much more opaque
                    Color(.sRGB, red: 0.12, green: 0.12, blue: 0.12, opacity: 0.95)  // Strong dark cards
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.thinMaterial) // Subtle blur behind
                )

            // Strong border for clear definition
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .light ?
                    Color(.sRGB, red: 0.85, green: 0.87, blue: 0.9, opacity: 1.0) : // Solid border
                    Color(.sRGB, red: 0.3, green: 0.3, blue: 0.3, opacity: 1.0),
                    lineWidth: 1
                )

            // Subtle colored accent border (inner border)
            if let accentColor = accentColor {
                RoundedRectangle(cornerRadius: 11.5)
                    .stroke(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.20),
                                accentColor.opacity(0.12),
                                accentColor.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .padding(0.5) // Inset slightly from outer border
            }
        }
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Subtle content type badge
                Text(contentTypeInfo.name.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(contentTypeInfo.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(contentTypeInfo.color.opacity(0.08))
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
                    .foregroundColor(colorScheme == .light ?
                        Color(.sRGB, red: 0.581, green: 0.639, blue: 0.722, opacity: 1.0) : // #94a3b8
                        Color(.sRGB, red: 0.7, green: 0.7, blue: 0.7, opacity: 1.0)
                    )

                Spacer()

                // Timestamp - exact colors from HTML reference
                Text(timeAgoText)
                    .font(.system(size: 11))
                    .foregroundColor(colorScheme == .light ?
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
            return "\(Int(content.dimensions.width)) × \(Int(content.dimensions.height))"
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

    private var timeAgoText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.timestamps.createdAt, relativeTo: Date())
    }
    
    

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Action Methods

    private func copyItem() {
        // Show subtle copy feedback animation
        withAnimation(.easeInOut(duration: 0.15)) {
            showCopyFeedback = true
        }

        // Reset feedback after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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

        // Increased delay to 250ms to ensure:
        // 1. Overlay hide animation completes (200ms)
        // 2. Focus restored to previous app/text field via NSWorkspace
        // 3. macOS processes focus change
        // 4. THEN paste into the now-focused text field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSLog("📋 Double-click paste executing after overlay hidden and focus restored")

            // Add haptic feedback
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

            // NOW paste into restored text field
            self.viewModel.pasteItem(self.item)
        }
    }


    // MARK: - Drag and Drop Support

    /// Provides NSItemProvider for tagging via drag-and-drop
    private func provideDragDataForTagging() -> NSItemProvider {
        // For tagging, provide the item ID as a string
        return NSItemProvider(object: item.id.uuidString as NSString)
    }

    /// Provides NSItemProvider for drag-and-drop with proper file handling
    private func provideDragData() -> NSItemProvider {
        switch item.content {
        case .image(_):
            // For images, use the pre-cached file path (created async in onAppear)
            // This provides instant drag with zero latency
            if let cachedPath = cachedImagePath {
                let fileURL = URL(fileURLWithPath: cachedPath)
                let provider = NSItemProvider(contentsOf: fileURL)!
                return provider
            } else {
                // Fallback if cache isn't ready yet (shouldn't happen)
                return NSItemProvider(object: "[Image]" as NSString)
            }

        default:
            // For text and other types, provide string data
            return NSItemProvider(object: dragData as NSString)
        }
    }

    private var dragData: String {
        switch item.content {
        case .text(let textContent):
            return textContent.plainText
        case .richText(let richContent):
            return richContent.plainTextFallback
        case .image(_):
            // For images, use cached temporary file path or fallback to description
            return cachedImagePath ?? "[Image: \(item.metadata.preview ?? "Untitled")]"
        case .file(let fileContent):
            // For files, return the file paths as text
            return fileContent.urls.map { $0.path }.joined(separator: "\n")
        case .link(let linkContent):
            return linkContent.url.absoluteString
        case .code(let codeContent):
            return codeContent.code
        case .color(let colorContent):
            return colorContent.hexValue
        case .snippet(let snippetContent):
            return snippetContent.content
        case .multiple(let multiContent):
            // For multiple items, return the first text-like item
            for subItem in multiContent.items {
                switch subItem {
                case .text(let textContent):
                    return textContent.plainText
                case .richText(let richContent):
                    return richContent.plainTextFallback
                case .link(let linkContent):
                    return linkContent.url.absoluteString
                case .code(let codeContent):
                    return codeContent.code
                case .color(let colorContent):
                    return colorContent.hexValue
                default:
                    continue
                }
            }
            return "Multiple items"
        }
    }

    private func createTemporaryImageFile(from imageContent: ImageContent) -> String? {
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
    }

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

    private var dragPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Type badge
            Text(contentTypeInfo.name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(contentTypeInfo.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(contentTypeInfo.color.opacity(0.15))
                )

            // Content preview
            Text(dragPreviewText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Drag indicator
            HStack {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Drag to paste")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var dragPreviewText: String {
        let text = dragData
        let maxLength = 60
        return text.count > maxLength ?
            String(text.prefix(maxLength)) + "..." :
            text
    }

    // MARK: - Source App Icon

    /// Converts stored icon Data (TIFF format) to SwiftUI Image
    private func iconImage(from data: Data) -> Image? {
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
    }

    /// App icon badge view showing the source application
    private var appIconBadge: some View {
        Group {
            if let iconData = item.source.applicationIcon {
                // Debug logging for icon data
                let _ = NSLog("🎯 App icon data - BundleID: \(item.source.applicationBundleID ?? "nil"), Name: \(item.source.applicationName ?? "nil"), Icon size: \(iconData.count) bytes")

                if let iconImage = iconImage(from: iconData) {
                    iconImage
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
                    let _ = NSLog("❌ Failed to convert icon data to NSImage for: \(item.source.applicationName ?? "Unknown")")
                    // Fallback when icon data exists but conversion fails
                    Image(systemName: "app.badge")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .light ?
                            Color(.sRGB, red: 0.581, green: 0.639, blue: 0.722, opacity: 1.0) :
                            Color(.sRGB, red: 0.7, green: 0.7, blue: 0.7, opacity: 1.0)
                        )
                        .frame(width: 22, height: 22)
                }
            } else {
                let _ = NSLog("⚠️ No icon data for app: \(item.source.applicationName ?? "Unknown"), BundleID: \(item.source.applicationBundleID ?? "nil")")
                // Fallback to SF Symbol if no app icon available
                Image(systemName: "app.badge")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .light ?
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
                    let (r, g, b) = tag.color.rgbComponents
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: r, green: g, blue: b))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                            )

                        Text(tag.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(red: r, green: g, blue: b).opacity(0.15))
                    )
                }

                if itemTags.count > 2 {
                    Text("+\(itemTags.count - 2)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
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
                            let (r, g, b) = tag.color.rgbComponents
                            Circle()
                                .fill(Color(red: r, green: g, blue: b))
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

    private func loadTags() {
        allTags = TagService.shared.getAllTags()

        Task {
            let tags = await viewModel.getTagsForItem(itemId: item.id)
            await MainActor.run {
                itemTags = tags
            }
        }
    }

    private func toggleTag(_ tag: Tag) {
        if itemTags.contains(where: { $0.id == tag.id }) {
            // Remove tag
            viewModel.removeTagFromItem(tagId: tag.id, itemId: item.id)
            itemTags.removeAll { $0.id == tag.id }
        } else {
            // Add tag
            viewModel.addTagToItem(tagId: tag.id, itemId: item.id)
            itemTags.append(tag)
        }
    }

    // MARK: - Color Extraction

    /// Extracts accent color from app icon for card theming
    private func extractAccentColor() async {
        let appName = item.source.applicationName ?? "Unknown"
        NSLog("🎨 Starting color extraction for: \(appName)")

        // Check cache first
        if let bundleID = item.source.applicationBundleID {
            if let cachedColor = await AppIconColorCache.shared.getColor(for: bundleID) {
                NSLog("✅ Using cached color for: \(appName)")
                accentColor = cachedColor
                return
            }
        }

        // Extract color from icon data
        guard let iconData = item.source.applicationIcon else {
            NSLog("⚠️ No icon data to extract color from for: \(appName)")
            return
        }

        guard let nsImage = NSImage(data: iconData) else {
            NSLog("❌ Failed to create NSImage from icon data for: \(appName)")
            return
        }

        guard let extractedColor = nsImage.extractDominantColor() else {
            NSLog("❌ Failed to extract dominant color for: \(appName)")
            return
        }

        NSLog("✅ Successfully extracted color for: \(appName)")

        // Cache the extracted color
        if let bundleID = item.source.applicationBundleID {
            await AppIconColorCache.shared.setColor(extractedColor, for: bundleID)
        }

        accentColor = extractedColor
        NSLog("🎨 Applied accent color to card for: \(appName)")
    }
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

