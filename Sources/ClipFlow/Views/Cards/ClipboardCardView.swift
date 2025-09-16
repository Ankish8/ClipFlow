import SwiftUI
import ClipFlowCore

struct ClipboardCardView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool

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
                .stroke(isSelected ? contentTypeInfo.color : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .shadow(
            color: isSelected ? contentTypeInfo.color.opacity(0.3) : Color.black.opacity(0.2),
            radius: isSelected ? 8 : 4,
            x: 0,
            y: 2
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
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
            // Base background - darker and more solid like Paste
            Color.black.opacity(0.4)

            // Content type accent gradient
            LinearGradient(
                colors: [
                    contentTypeInfo.color.opacity(0.15),
                    Color.clear,
                    contentTypeInfo.color.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle inner border for depth
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        }
    }

    private var cardHeader: some View {
        HStack {
            // Content type badge
            HStack(spacing: 4) {
                Image(systemName: contentTypeInfo.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(contentTypeInfo.name)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(contentTypeInfo.color)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Spacer()

            // Index number
            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Color.white.opacity(0.2))
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