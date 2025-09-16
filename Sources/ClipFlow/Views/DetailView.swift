import SwiftUI
import ClipFlowCore
import ClipFlowAPI

struct DetailView: View {
    let item: ClipboardItem
    let viewModel: ClipboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with actions
            DetailHeader(item: item, viewModel: viewModel)

            // Content preview
            ContentPreview(content: item.content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Metadata footer
            MetadataFooter(item: item)
        }
        .padding(16)
        .background(.regularMaterial)
    }
}

struct DetailHeader: View {
    let item: ClipboardItem
    let viewModel: ClipboardViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ContentTypeIcon(content: item.content)
                    Text(item.content.typeDisplayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Text("From \(item.source.applicationName ?? "Unknown")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    viewModel.toggleFavorite(for: item)
                } label: {
                    Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(item.isFavorite ? .red : .primary)
                }
                .help("Toggle Favorite")

                Button {
                    viewModel.togglePin(for: item)
                } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .foregroundColor(item.isPinned ? .orange : .primary)
                }
                .help("Toggle Pin")

                Menu {
                    ForEach(TransformAction.allCases, id: \.self) { transform in
                        Button(transform.displayName) {
                            viewModel.pasteItem(item, transform: transform)
                        }
                    }
                } label: {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.primary)
                }
                .help("Transform and Paste")

                Button {
                    viewModel.pasteItem(item)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundColor(.blue)
                }
                .help("Paste")
                .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.borderless)
        }
    }
}

struct ContentPreview: View {
    let content: ClipboardContent

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Group {
                switch content {
                case .text(let textContent):
                    TextContentView(content: textContent)
                case .richText(let richContent):
                    RichTextContentView(content: richContent)
                case .image(let imageContent):
                    ImageContentView(content: imageContent)
                case .file(let fileContent):
                    FileContentView(content: fileContent)
                case .link(let linkContent):
                    LinkContentView(content: linkContent)
                case .code(let codeContent):
                    CodeContentView(content: codeContent)
                case .color(let colorContent):
                    ColorContentView(content: colorContent)
                case .snippet(let snippetContent):
                    SnippetContentView(content: snippetContent)
                case .multiple(let multiContent):
                    MultipleContentView(content: multiContent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
}

// MARK: - Content Type Views

struct TextContentView: View {
    let content: TextContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(content.plainText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            if content.isEmail || content.isPhoneNumber || content.isURL {
                HStack {
                    if content.isEmail {
                        Label("Email detected", systemImage: "envelope")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    if content.isPhoneNumber {
                        Label("Phone detected", systemImage: "phone")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    if content.isURL {
                        Label("URL detected", systemImage: "link")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }
}

struct RichTextContentView: View {
    let content: RichTextContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show rich content if available, fallback to plain text
            if let attributedString = try? NSAttributedString(data: content.attributedStringData, options: [:], documentAttributes: nil) {
                Text(AttributedString(attributedString))
                    .textSelection(.enabled)
            } else {
                Text(content.plainTextFallback)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
}

struct ImageContentView: View {
    let content: ImageContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let nsImage = NSImage(data: content.data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 300)
            } else {
                Label("Image preview not available", systemImage: "photo")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Format: \(content.format)")
                Text("Size: \(ByteCountFormatter().string(fromByteCount: Int64(content.data.count)))")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}

struct FileContentView: View {
    let content: FileContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(content.urls.enumerated()), id: \.offset) { index, url in
                HStack {
                    Image(systemName: "doc")
                        .foregroundColor(.orange)
                    Text(url.lastPathComponent)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct LinkContentView: View {
    let content: LinkContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(destination: content.url) {
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(.blue)
                    Text(content.url.absoluteString)
                        .foregroundColor(.blue)
                        .underline()
                }
            }

            if let title = content.title {
                Text(title)
                    .font(.headline)
            }

            if let description = content.description {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct CodeContentView: View {
    let content: CodeContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Language: \(content.language)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            Text(content.code)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

struct ColorContentView: View {
    let content: ColorContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: content.red, green: content.green, blue: content.blue, opacity: content.alpha))
                    .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 4) {
                    Text("RGB: \(Int(content.red * 255)), \(Int(content.green * 255)), \(Int(content.blue * 255))")
                    Text("Hex: \(content.hexString)")
                    Text("Alpha: \(content.alpha, specifier: "%.2f")")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
}

struct SnippetContentView: View {
    let content: SnippetContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(content.title)
                .font(.headline)

            Text(content.content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

            if !content.placeholders.isEmpty {
                Text("Placeholders: \(content.placeholders.map { $0.name }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct MultipleContentView: View {
    let content: MultiContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Multiple items (\(content.items.count))")
                .font(.headline)

            ForEach(Array(content.items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ContentTypeIcon(content: item)
                        Text("\(index + 1). \(item.typeDisplayName)")
                            .font(.subheadline)
                    }
                    Text(item.displayText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

struct MetadataFooter: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created: \(item.timestamps.createdAt, style: .date) at \(item.timestamps.createdAt, style: .time)")
                    Text("Size: \(ByteCountFormatter().string(fromByteCount: item.metadata.size))")
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Hash: \(String(item.metadata.hash.prefix(8)))")
                    if item.security.isEncrypted {
                        Text("🔒 Encrypted")
                            .foregroundColor(.blue)
                    }
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }
}

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text("No Item Selected")
                    .font(.title2)
                    .foregroundColor(.primary)

                Text("Select an item from the clipboard history to view details")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}