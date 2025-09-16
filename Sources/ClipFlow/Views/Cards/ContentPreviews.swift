import SwiftUI
import ClipFlowCore
import AppKit

// MARK: - Text Preview Card
struct TextPreviewCard: View {
    let content: TextContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.plainText)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if content.plainText.count > 100 {
                Text("...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Rich Text Preview Card
struct RichTextPreviewCard: View {
    let content: RichTextContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Show formatted preview if possible, fallback to plain text
            if let htmlString = content.htmlString, !htmlString.isEmpty {
                Text("Rich Text Content")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                Text(content.plainTextFallback)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(3)
            } else {
                Text(content.plainTextFallback)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Image Preview Card
struct ImagePreviewCard: View {
    let content: ImageContent

    var body: some View {
        VStack(spacing: 0) {
            // Image preview
            if let nsImage = NSImage(data: content.data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }

            Spacer(minLength: 4)

            // Image info
            Text("\(content.format.rawValue.uppercased())")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Preview Card
struct FilePreviewCard: View {
    let content: FileContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // File icon and name
            HStack(spacing: 6) {
                Image(systemName: fileIcon)
                    .font(.system(size: 16))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text(content.fileName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if content.urls.count > 1 {
                        Text("\(content.urls.count) files")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // File type and size
            HStack {
                Text(content.fileType.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text(formatFileSize(content.fileSize))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var fileIcon: String {
        let ext = content.fileType.lowercased()
        switch ext {
        case "pdf":
            return "doc.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "xls", "xlsx":
            return "tablecells.fill"
        case "ppt", "pptx":
            return "play.rectangle.fill"
        case "zip", "rar", "7z":
            return "archivebox.fill"
        case "jpg", "jpeg", "png", "gif", "bmp":
            return "photo.fill"
        case "mp4", "mov", "avi":
            return "video.fill"
        case "mp3", "wav", "aac":
            return "music.note"
        case "txt", "md":
            return "doc.text"
        default:
            return "doc"
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Link Preview Card
struct LinkPreviewCard: View {
    let content: LinkContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Link icon and title
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 14))
                    .foregroundColor(.cyan)

                VStack(alignment: .leading, spacing: 1) {
                    if let title = content.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    } else {
                        Text("Link")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
            }

            Spacer()

            // URL
            Text(content.url.absoluteString)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Domain
            if let host = content.url.host {
                Text(host)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.cyan)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Color Preview Card
struct ColorPreviewCard: View {
    let content: ColorContent

    var body: some View {
        VStack(spacing: 6) {
            // Color swatch
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: content.red, green: content.green, blue: content.blue, opacity: content.alpha))
                .frame(height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            Spacer()

            // Color values
            VStack(alignment: .leading, spacing: 2) {
                Text(content.hexValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)

                Text("RGB(\(Int(content.red * 255)), \(Int(content.green * 255)), \(Int(content.blue * 255)))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Multi Content Preview Card
struct MultiPreviewCard: View {
    let content: MultiContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Multi-content icon
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(content.items.count) Items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                    Text("Multiple content types")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Content types summary
            let contentTypes = content.items.map { $0.contentType }.removingDuplicates()
            Text(contentTypes.joined(separator: ", "))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// Helper extension for removing duplicates
extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        Array(Set(self))
    }
}