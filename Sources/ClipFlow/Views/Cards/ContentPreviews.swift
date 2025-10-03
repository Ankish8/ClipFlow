import SwiftUI
import ClipFlowCore
import AppKit

// MARK: - Text Preview Card
struct TextPreviewCard: View {
    let content: TextContent
    @Environment(\.colorScheme) var colorScheme

    private var detectedColor: Color? {
        let text = content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return parseHexColor(text)
    }

    private func parseHexColor(_ hex: String) -> Color? {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.hasPrefix("#"), hex.count == 7 else { return nil }

        let hexValue = String(hex.dropFirst())
        guard let intValue = Int(hexValue, radix: 16) else { return nil }

        let red = Double((intValue & 0xFF0000) >> 16) / 255.0
        let green = Double((intValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(intValue & 0x0000FF) / 255.0

        return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }

    var body: some View {
        if let color = detectedColor {
            // Display as color preview
            VStack(spacing: 12) {
                // Color swatch
                RoundedRectangle(cornerRadius: 12)
                    .fill(color)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )

                Spacer()

                // Color information
                VStack(alignment: .leading, spacing: 6) {
                    Text(content.plainText.uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    if let rgbComponents = parseRGBFromHex(content.plainText) {
                        Text("RGB(\(rgbComponents.0), \(rgbComponents.1), \(rgbComponents.2))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Display as regular text
            VStack(alignment: .leading, spacing: 8) {
                // Content title - exact colors from HTML reference
                if content.plainText.count > 50 {
                    Text(String(content.plainText.prefix(40)) + (content.plainText.count > 40 ? "..." : ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .light ?
                            Color(.sRGB, red: 0.118, green: 0.161, blue: 0.231, opacity: 1.0) : // #1e293b
                            Color(.sRGB, red: 0.9, green: 0.9, blue: 0.9, opacity: 1.0)
                        )
                        .lineLimit(1)
                }

                // Main content - exact colors from HTML reference
                if content.plainText.count <= 50 {
                    Text(content.plainText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .light ?
                            Color(.sRGB, red: 0.118, green: 0.161, blue: 0.231, opacity: 1.0) : // #1e293b
                            Color(.sRGB, red: 0.9, green: 0.9, blue: 0.9, opacity: 1.0)
                        )
                        .lineLimit(3)
                } else {
                    Text(content.plainText)
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .light ?
                            Color(.sRGB, red: 0.2, green: 0.322, blue: 0.333, opacity: 1.0) : // #334155
                            Color(.sRGB, red: 0.8, green: 0.8, blue: 0.8, opacity: 1.0)
                        )
                        .lineLimit(6)
                        .lineSpacing(1.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func parseRGBFromHex(_ hex: String) -> (Int, Int, Int)? {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.hasPrefix("#"), hex.count == 7 else { return nil }

        let hexValue = String(hex.dropFirst())
        guard let intValue = Int(hexValue, radix: 16) else { return nil }

        let red = (intValue & 0xFF0000) >> 16
        let green = (intValue & 0x00FF00) >> 8
        let blue = intValue & 0x0000FF

        return (red, green, blue)
    }
}

// MARK: - Rich Text Preview Card
struct RichTextPreviewCard: View {
    let content: RichTextContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Content title
            if content.plainTextFallback.count > 50 {
                Text(String(content.plainTextFallback.prefix(40)) + (content.plainTextFallback.count > 40 ? "..." : ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            // Main content
            if content.plainTextFallback.count <= 50 {
                Text(content.plainTextFallback)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(3)
            } else {
                Text(content.plainTextFallback)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(6)
                    .lineSpacing(1.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Image Preview Card
struct ImagePreviewCard: View {
    let content: ImageContent

    var body: some View {
        VStack(spacing: 6) {
            // Image preview - larger for better visibility
            if let nsImage = NSImage(data: content.data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .font(.system(size: 24))
                    )
            }

            Spacer(minLength: 4)

            // Image info - compact layout
            VStack(spacing: 3) {
                Text("\(content.format.rawValue.uppercased())")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)

                Text("\(Int(content.dimensions.width)) × \(Int(content.dimensions.height))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Preview Card
struct FilePreviewCard: View {
    let content: FileContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // File icon and name - larger layout
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: fileIcon)
                        .font(.system(size: 24))
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.fileName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(2)

                        if content.urls.count > 1 {
                            Text("\(content.urls.count) files")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // File path or additional info if space permits
                if let firstURL = content.urls.first {
                    Text(firstURL.lastPathComponent)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // File type and size - larger and more prominent
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(content.fileType.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text(formatFileSize(content.fileSize))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
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
        VStack(alignment: .leading, spacing: 12) {
            // Link icon and title - larger layout
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 18))
                        .foregroundColor(.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        if let title = content.title, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(3)
                        } else {
                            Text("Web Link")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }
                }

                // Domain prominently displayed
                if let host = content.url.host {
                    Text(host)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.cyan)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Full URL at bottom
            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.8))

                Text(content.url.absoluteString)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Color Preview Card
struct ColorPreviewCard: View {
    let content: ColorContent

    var body: some View {
        VStack(spacing: 12) {
            // Color swatch - much larger
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: content.red, green: content.green, blue: content.blue, opacity: content.alpha))
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            Spacer()

            // Color values - larger and more detailed
            VStack(alignment: .leading, spacing: 6) {
                Text(content.hexValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("RGB(\(Int(content.red * 255)), \(Int(content.green * 255)), \(Int(content.blue * 255)))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if content.alpha < 1.0 {
                        Text("Alpha: \(String(format: "%.2f", content.alpha))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Multi Content Preview Card
struct MultiPreviewCard: View {
    let content: MultiContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Multi-content icon and header
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 20))
                        .foregroundColor(.purple)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(content.items.count) Items")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Multiple content types")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                // Show breakdown of content types
                let contentTypes = content.items.map { $0.contentType }.removingDuplicates()
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(contentTypes.prefix(4), id: \.self) { type in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.secondary.opacity(0.6))
                                .frame(width: 4, height: 4)
                            Text(type.capitalized)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    if contentTypes.count > 4 {
                        Text("+ \(contentTypes.count - 4) more...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }

            Spacer()
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