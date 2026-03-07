import SwiftUI
import ClipFlowCore

/// Floating Quick Look panel that appears above the card strip when Spacebar is pressed.
/// Shows content type, full preview, stats, and an Edit button.
struct QuickLookPreviewView: View {
    let item: ClipboardItem
    let onEdit: () -> Void
    let onDismiss: () -> Void

    private let contentTypeInfo: ContentTypeInfo

    init(item: ClipboardItem, onEdit: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.item = item
        self.onEdit = onEdit
        self.onDismiss = onDismiss
        self.contentTypeInfo = ContentTypeInfo.from(item.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: type icon + label (left), Edit button (right)
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: contentTypeInfo.icon)
                        .foregroundStyle(contentTypeInfo.color)
                    Text(contentTypeInfo.name)
                        .font(.headline)
                }

                Spacer()

                if isEditable {
                    Button("Edit") { onEdit() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 12)

            // Body: scrollable content preview
            ScrollView {
                contentPreview
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().padding(.horizontal, 12)

            // Footer: stats bar
            HStack {
                Text(statsText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThickMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Content Preview

    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .text(let c):
            Text(c.plainText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

        case .richText(let c):
            Text(c.plainTextFallback)
                .textSelection(.enabled)

        case .link(let c):
            VStack(alignment: .leading, spacing: 4) {
                if let title = c.title, title != c.url.absoluteString {
                    Text(title).font(.headline)
                }
                Link(c.url.absoluteString, destination: c.url)
                    .font(.system(.body, design: .monospaced))
                if let desc = c.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

        case .image(let c):
            if let img = NSImage(data: c.data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        case .file(let c):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(c.urls, id: \.absoluteString) { url in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                        Text(url.lastPathComponent)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

        case .code(let c):
            Text(c.code)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

        case .color(let c):
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha))
                    .frame(width: 60, height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                VStack(alignment: .leading) {
                    Text(c.hexValue).font(.system(.title3, design: .monospaced))
                    Text("R: \(Int(c.red * 255)) G: \(Int(c.green * 255)) B: \(Int(c.blue * 255))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .snippet(let c):
            Text(c.content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

        case .multiple(let c):
            Text(c.description)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Stats

    private var statsText: String {
        switch item.content {
        case .text(let c):
            return textStats(c.plainText)
        case .richText(let c):
            return textStats(c.plainTextFallback)
        case .code(let c):
            return textStats(c.code)
        case .snippet(let c):
            return textStats(c.content)
        case .image(let c):
            let w = Int(c.dimensions.width)
            let h = Int(c.dimensions.height)
            return "\(w) × \(h) · \(formatBytes(c.data.count))"
        case .file(let c):
            let count = c.urls.count
            return "\(count) \(count == 1 ? "file" : "files") · \(formatBytes(Int(c.fileSize)))"
        case .link(let c):
            return c.url.host ?? c.url.absoluteString
        case .color(let c):
            return c.hexValue
        case .multiple(let c):
            return "\(c.items.count) items"
        }
    }

    private func textStats(_ text: String) -> String {
        let chars = text.count
        let words = text.split(separator: " ", omittingEmptySubsequences: true).count
        let lines = text.components(separatedBy: .newlines).count
        return "\(chars) characters · \(words) words · \(lines) \(lines == 1 ? "line" : "lines")"
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Editability

    private var isEditable: Bool {
        switch item.content {
        case .text, .link, .code, .snippet: return true
        default: return false
        }
    }
}
