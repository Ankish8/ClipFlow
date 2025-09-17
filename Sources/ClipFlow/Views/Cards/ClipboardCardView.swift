import SwiftUI
import ClipFlowCore
import UniformTypeIdentifiers

struct ClipboardCardView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let viewModel: ClipboardViewModel
    @State private var isHovering = false
    @State private var hoveredButton: String? = nil
    @State private var isDeleting = false
    @State private var cachedImagePath: String? = nil

    private var contentTypeInfo: ContentTypeInfo {
        ContentTypeInfo.from(item.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header with type badge and index
            cardHeader

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
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .scaleEffect(isDeleting ? 0.8 : 1.0)
        .offset(y: isHovering ? -1 : 0) // transform: translateY(-1px)
        .offset(y: isDeleting ? -20 : 0)
        .opacity(isDeleting ? 0 : 1)
        .shadow(
            color: colorScheme == .light ?
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: isHovering ? 0.05 : 0.0) : // rgba(0, 0, 0, 0.05)
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: isHovering ? 0.3 : 0.0),
            radius: isHovering ? 6 : 0,
            x: 0,
            y: isHovering ? 4 : 0
        )
        .shadow(
            color: colorScheme == .light ?
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: isHovering ? 0.08 : 0.0) : // rgba(0, 0, 0, 0.08)
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: isHovering ? 0.2 : 0.0),
            radius: isHovering ? 3 : 0,
            x: 0,
            y: isHovering ? 1 : 0
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.easeInOut(duration: 0.3), value: isDeleting)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .draggable(dragData) {
            dragPreview
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { _ in
                    NotificationCenter.default.post(name: .startDragging, object: nil)
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .stopDragging, object: nil)
                    }
                }
        )
        .overlay(alignment: .topTrailing) {
            if isHovering && !isDeleting {
                quickActionButtons
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        // Keep the card hover state active when hovering over buttons
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isHovering = hovering
                        }
                    }
            }
        }
        .onAppear {
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
        }
        .shadow(
            color: colorScheme == .light ?
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.12) : // Much stronger shadow
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.4),
            radius: 8,
            x: 0,
            y: 4
        )
        .shadow(
            color: colorScheme == .light ?
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.08) : // Secondary shadow
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.2),
            radius: 3,
            x: 0,
            y: 2
        )
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
            }
            
            // Tag badges
            if !item.tags.isEmpty {
                tagBadgesView
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
    
    private var tagBadgesView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(item.tags.sorted()), id: \.self) { tagName in
                    TagBadgeView(tagName: tagName, tagColor: nil)
                        .onTapGesture {
                            // Handle tag tap - could filter by this tag
                            handleTagTap(tagName)
                        }
                }
            }
            .padding(.horizontal, -2) // Compensate for card padding
        }
    }
    
    private func handleTagTap(_ tagName: String) {
        // Notify view model to filter by this tag
        // This will be implemented when we add tag filtering
        print("Tag tapped: \(tagName)")
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Quick Actions

    private var quickActionButtons: some View {
        HStack(spacing: 8) {
            // Copy action
            quickActionButton(icon: "doc.on.doc", action: copyItem, color: .primary)
            
            // Delete action
            quickActionButton(icon: "trash", action: deleteItem, color: .primary)
            
            // Pin/Favorite action
            quickActionButton(icon: item.isFavorite ? "star.fill" : "star", action: pinItem, color: .primary)
            
            // Tag assignment action
            quickActionButton(icon: "tag", action: assignTags, color: .blue)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .light ? 
                    Color(.sRGB, red: 0.98, green: 0.98, blue: 0.99, opacity: 0.95) :
                    Color(.sRGB, red: 0.15, green: 0.15, blue: 0.16, opacity: 0.95)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colorScheme == .light ?
                            Color(.sRGB, red: 0.85, green: 0.87, blue: 0.9, opacity: 0.8) :
                            Color(.sRGB, red: 0.35, green: 0.35, blue: 0.36, opacity: 0.8),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: colorScheme == .light ?
                        Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.1) :
                        Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.3),
                    radius: 4,
                    x: 0,
                    y: 2
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(8)
    }

    private func quickActionButton(icon: String, action: @escaping () -> Void, color: Color) -> some View {
        Button(action: {
            // Add haptic feedback
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .light ? color : color.opacity(0.9))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuickActionButtonStyle(color: color, colorScheme: colorScheme))
    }

    // MARK: - Action Methods

    private func copyItem() {
        viewModel.pasteItem(item)
    }

    private func deleteItem() {
        // Trigger delete animation
        withAnimation(.easeInOut(duration: 0.3)) {
            isDeleting = true
        }
        
        // Perform actual delete after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            viewModel.deleteItem(item)
        }
    }

    private func pinItem() {
        viewModel.toggleFavorite(for: item)
    }
    
    private func assignTags() {
        viewModel.assignTags(to: item)
    }

    // MARK: - Drag and Drop Support

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
}

// Custom button style for quick action buttons
struct QuickActionButtonStyle: ButtonStyle {
    let color: Color
    let colorScheme: ColorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(colorScheme == .light ? 
                (configuration.isPressed ? Color.primary.opacity(0.7) : Color.primary.opacity(0.8)) :
                (configuration.isPressed ? Color.primary.opacity(0.6) : Color.primary.opacity(0.7))
            )
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? 
                        (colorScheme == .light ? Color.primary.opacity(0.15) : Color.primary.opacity(0.25)) :
                        (colorScheme == .light ? Color.primary.opacity(0.06) : Color.primary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(configuration.isPressed ? Color.primary.opacity(0.4) : Color.primary.opacity(0.2), lineWidth: configuration.isPressed ? 1 : 0.5)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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
            return ContentTypeInfo(name: "Rich Text", icon: "doc.richtext", color: .purple)
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