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
        .frame(width: cardWidth, height: 250)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .offset(y: isHovering ? -1 : 0) // transform: translateY(-1px)
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

    // MARK: - Quick Actions

    private var quickActionButtons: some View {
        HStack(spacing: 2) {
            // Copy action
            quickActionButton(icon: "doc.on.doc", action: copyItem)

            // Delete action
            quickActionButton(icon: "trash", action: deleteItem)

            // Pin/Favorite action
            quickActionButton(icon: "star", action: pinItem)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .opacity(0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(6)
    }

    private func quickActionButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.15))
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
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