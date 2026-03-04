import SwiftUI
import ClipFlowCore
import AppKit

// MARK: - Text Preview Card
struct TextPreviewCard: View {
    let content: TextContent
    @Environment(\.colorScheme) var colorScheme

    // Parse hex once — returns (swiftUIColor, luminance) or nil if not a hex color
    private var detectedColorInfo: (color: Color, luminance: Double)? {
        let text = content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("#"), text.count == 7,
              let intValue = Int(String(text.dropFirst()), radix: 16) else { return nil }
        let r = Double((intValue & 0xFF0000) >> 16) / 255.0
        let g = Double((intValue & 0x00FF00) >> 8) / 255.0
        let b = Double(intValue & 0x0000FF) / 255.0
        return (Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0), 0.299 * r + 0.587 * g + 0.114 * b)
    }

    var body: some View {
        if let info = detectedColorInfo {
            // Display as color preview with overlaid hex code (no RGB)
            let contrastingColor: Color = info.luminance > 0.5 ? .black : .white
            RoundedRectangle(cornerRadius: 12)
                .fill(info.color)
                .overlay(
                    // Hex code centered on color with intelligent contrast
                    Text(content.plainText.uppercased())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(contrastingColor)
                )
                .overlay(
                    // Border for better definition
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .padding(.bottom, 16) // Bottom padding only
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Display as regular text
            VStack(alignment: .leading, spacing: 8) {
                // Content title - exact colors from HTML reference
                if content.plainText.count > 50 {
                    Text(String(content.plainText.prefix(40)) + (content.plainText.count > 40 ? "..." : ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(colorScheme == .light ?
                            Color(.sRGB, red: 0.118, green: 0.161, blue: 0.231, opacity: 1.0) : // #1e293b
                            Color(.sRGB, red: 0.9, green: 0.9, blue: 0.9, opacity: 1.0)
                        )
                        .lineLimit(1)
                }

                // Main content - exact colors from HTML reference
                if content.plainText.count <= 50 {
                    Text(content.plainText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(colorScheme == .light ?
                            Color(.sRGB, red: 0.118, green: 0.161, blue: 0.231, opacity: 1.0) : // #1e293b
                            Color(.sRGB, red: 0.9, green: 0.9, blue: 0.9, opacity: 1.0)
                        )
                        .lineLimit(3)
                } else {
                    Text(content.plainText)
                        .font(.system(size: 14))
                        .foregroundStyle(colorScheme == .light ?
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
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            // Main content
            if content.plainTextFallback.count <= 50 {
                Text(content.plainTextFallback)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            } else {
                Text(content.plainTextFallback)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
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
    @State private var renderedImage: Image? = nil

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let img = renderedImage {
                    img
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
                                .foregroundStyle(.secondary)
                                .font(.system(size: 24))
                        )
                }
            }

            Spacer(minLength: 4)

            // Image info - compact layout
            VStack(spacing: 3) {
                Text("\(content.format.rawValue.uppercased())")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)

                Text("\(Int(content.dimensions.width)) × \(Int(content.dimensions.height))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let data = content.data
            let nsImage = await Task.detached(priority: .utility) {
                NSImage(data: data)
            }.value
            if let nsImage {
                renderedImage = Image(nsImage: nsImage)
            }
        }
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
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.fileName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if content.urls.count > 1 {
                            Text("\(content.urls.count) files")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // File path or additional info if space permits
                if let firstURL = content.urls.first {
                    Text(firstURL.lastPathComponent)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // File type and size - larger and more prominent
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(content.fileType.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(formatFileSize(content.fileSize))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
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

    private static let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()

    private func formatFileSize(_ bytes: Int64) -> String {
        Self.byteCountFormatter.string(fromByteCount: bytes)
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
                        .foregroundStyle(.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        if let title = content.title, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                        } else {
                            Text("Web Link")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }

                // Domain prominently displayed
                if let host = content.url.host {
                    Text(host)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Full URL at bottom
            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.8))

                Text(content.url.absoluteString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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

    // Calculate luminance to determine if color is dark or light
    private var luminance: Double {
        // Using relative luminance formula: 0.299*R + 0.587*G + 0.114*B
        return 0.299 * content.red + 0.587 * content.green + 0.114 * content.blue
    }

    // Determine contrasting text color based on background luminance
    private var contrastingTextColor: Color {
        // If luminance > 0.5, background is light, use dark text
        // If luminance <= 0.5, background is dark, use light text
        return luminance > 0.5 ? Color.black : Color.white
    }

    var body: some View {
        // Large color swatch with overlaid hex code - no separate text section
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(red: content.red, green: content.green, blue: content.blue, opacity: content.alpha))
            .overlay(
                // Hex code centered on color with intelligent contrast
                Text(content.hexValue.uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(contrastingTextColor)
            )
            .overlay(
                // Border for better definition
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .padding(.bottom, 16) // Bottom padding only
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Multi Content Preview Card
struct MultiPreviewCard: View {
    let content: MultiContent
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Multi-content icon and header
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 20))
                        .foregroundStyle(colorScheme == .dark ? .white : .primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(content.items.count) Items")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("Multiple content types")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
                        }
                    }

                    if contentTypes.count > 4 {
                        Text("+ \(contentTypes.count - 4) more...")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary.opacity(0.8))
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