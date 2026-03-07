import SwiftUI
import ClipFlowCore
import AppKit

// MARK: - Text Preview Card
struct TextPreviewCard: View {
    let content: TextContent
    @Environment(\.colorScheme) var colorScheme

    // PERFORMANCE: Cache parsed color info — avoids string slicing + Int(radix:) on every render
    @State private var colorInfo: (color: Color, luminance: Double)? = nil

    private static func parseColorInfo(from text: String) -> (color: Color, luminance: Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), trimmed.count == 7,
              let intValue = Int(String(trimmed.dropFirst()), radix: 16) else { return nil }
        let r = Double((intValue & 0xFF0000) >> 16) / 255.0
        let g = Double((intValue & 0x00FF00) >> 8) / 255.0
        let b = Double(intValue & 0x0000FF) / 255.0
        return (Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0), 0.299 * r + 0.587 * g + 0.114 * b)
    }

    var body: some View {
        Group {
            if let info = colorInfo {
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
        .task {
            colorInfo = Self.parseColorInfo(from: content.plainText)
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
        Group {
            if let img = renderedImage {
                // Color.black.opacity(0.001) instead of Color.clear:
                // SwiftUI skips hit-testing on fully-transparent (clear) views,
                // creating a gap in the drag overlay's coverage. A near-zero
                // opacity registers as a valid hit target across the image region.
                Color.black.opacity(0.001)
                    .background(
                        img
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    )
                    .overlay(Color.white.opacity(0.06))
            } else {
                Color.secondary.opacity(0.15)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 24))
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let data = content.data
            let pair: (CGImage, CGFloat)? = await Task.detached(priority: .utility) {
                guard let nsImage = NSImage(data: data) else { return nil }
                // Detect actual pixel:point ratio from the bitmap representation.
                // 72 DPI PNG → scale 1.0; 144 DPI Retina screenshot → scale 2.0.
                let scale: CGFloat
                if let rep = nsImage.representations.first as? NSBitmapImageRep, rep.size.width > 0 {
                    scale = max(1.0, CGFloat(rep.pixelsWide) / rep.size.width)
                } else {
                    scale = 1.0
                }
                guard let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
                return (cg, scale)
            }.value
            if let (cg, scale) = pair {
                renderedImage = Image(cg, scale: scale, label: Text(""))
            }
        }
    }
}

// MARK: - File Preview Card
struct FilePreviewCard: View {
    let content: FileContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Filename as primary content — full width, no icon
            Text(content.fileName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(4)

            if content.urls.count > 1 {
                Text("\(content.urls.count) files")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // File type and size at bottom
            HStack {
                Text(content.fileType.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formatFileSize(content.fileSize))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
    @State private var faviconImage: Image?
    @State private var previewImage: Image?

    private var hasTitle: Bool {
        if let title = content.title, !title.isEmpty, title != content.url.absoluteString {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let preview = previewImage {
                // OG preview image — fills available space, text pinned at bottom
                preview
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Title + domain below image — compact, won't overflow
                if let title = content.title, !title.isEmpty, title != content.url.absoluteString {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    if let favicon = faviconImage {
                        favicon
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if let host = content.url.host {
                        Text(host)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                // No preview image — text-based layout
                if let title = content.title, !title.isEmpty, title != content.url.absoluteString {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                } else {
                    Text(content.url.absoluteString)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                }

                HStack(spacing: 5) {
                    if let favicon = faviconImage {
                        favicon
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if let host = content.url.host {
                        Text(host)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)

                if let desc = content.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: content.url) {
            // Decode favicon and preview image in parallel, off main thread
            let favData = content.faviconData
            let prevData = content.previewImageData

            let results: (fav: Image?, prev: Image?) = await Task.detached(priority: .utility) {
                let fav: Image? = {
                    guard let data = favData,
                          let ns = NSImage(data: data),
                          let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    else { return nil }
                    return Image(cg, scale: 1.0, label: Text(""))
                }()
                let prev: Image? = {
                    guard let data = prevData,
                          let ns = NSImage(data: data),
                          let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    else { return nil }
                    // Use scale 1.0 — OG images are web-resolution, not Retina
                    return Image(cg, scale: 1.0, label: Text(""))
                }()
                return (fav, prev)
            }.value

            faviconImage = results.fav
            previewImage = results.prev
        }
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
        VStack(alignment: .leading, spacing: 8) {
            // Item count — no icon
            Text("\(content.items.count) Items")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Multiple content types")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Content type breakdown
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
