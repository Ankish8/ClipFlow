import SwiftUI
import ClipFlowCore

struct ClipboardCardView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    @State private var isHovering = false

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
        .frame(width: cardWidth, height: 140)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .shadow(
            color: Color.black.opacity(isSelected ? 0.3 : 0.15),
            radius: isSelected ? 6 : 3,
            x: 0,
            y: 2
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovering || isSelected {
                quickActionButtons
            }
        }
    }

    private var cardWidth: CGFloat {
        switch item.content {
        case .image:
            return 180
        case .file:
            return 200
        case .link:
            return 220
        case .richText:
            return 240
        default:
            return 200
        }
    }

    private var cardBackground: some View {
        ZStack {
            // Base background - subtle and clean
            Color.white.opacity(0.08)

            // Very subtle content type hint
            RoundedRectangle(cornerRadius: 12)
                .fill(contentTypeInfo.color.opacity(0.03))

            // Minimal border for definition
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    private var cardHeader: some View {
        HStack {
            // Subtle content type indicator
            HStack(spacing: 3) {
                Image(systemName: contentTypeInfo.icon)
                    .font(.system(size: 9, weight: .medium))
                Text(contentTypeInfo.name)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Spacer()

            // Subtle index number
            Text("\(index)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 14, height: 14)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
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
        .padding(.horizontal, 8)
    }

    private var cardFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                // Metadata (character count, file size, etc.)
                Text(metadataText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                Spacer()

                // Source app icon if available
                if let appName = item.source.applicationName {
                    Text(appName)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Timestamp
            Text(timeAgoText)
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
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

    // MARK: - Quick Actions

    private var quickActionButtons: some View {
        HStack(spacing: 4) {
            // Copy action
            quickActionButton(icon: "doc.on.doc", action: copyItem)

            // Delete action
            quickActionButton(icon: "trash", action: deleteItem)

            // Pin/Favorite action
            quickActionButton(icon: "star", action: pinItem)
        }
        .padding(6)
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(4)
    }

    private func quickActionButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .onHover { hovering in
            // Add slight scale effect on hover
        }
    }

    // MARK: - Action Methods

    private func copyItem() {
        // Copy the item to clipboard again (useful for re-copying)
        NSPasteboard.general.clearContents()
        switch item.content {
        case .text(let textContent):
            NSPasteboard.general.setString(textContent.plainText, forType: .string)
        case .richText(let richContent):
            NSPasteboard.general.setString(richContent.plainTextFallback, forType: .string)
        case .image(let imageContent):
            NSPasteboard.general.setData(imageContent.data, forType: .png)
        default:
            break
        }
    }

    private func deleteItem() {
        // This will need to be connected to the ViewModel
        // For now, we'll post a notification
        NotificationCenter.default.post(
            name: .deleteClipboardItem,
            object: item
        )
    }

    private func pinItem() {
        // This will need to be connected to the ViewModel for pinning
        NotificationCenter.default.post(
            name: .pinClipboardItem,
            object: item
        )
    }
}

// Content type information for styling
struct ContentTypeInfo {
    let name: String
    let icon: String
    let color: Color

    static func from(_ content: ClipboardContent) -> ContentTypeInfo {
        switch content {
        case .text:
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
}