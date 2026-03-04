import SwiftUI
import ClipFlowCore
import ClipFlowAPI

struct ClipboardItemsList: View {
    let items: [ClipboardItem]
    @Binding var selectedItem: ClipboardItem?
    let viewModel: ClipboardViewModel

    // Native List selection binding uses item ID
    private var selectedItemID: Binding<ClipboardItem.ID?> {
        Binding(
            get: { selectedItem?.id },
            set: { newID in
                selectedItem = items.first { $0.id == newID }
            }
        )
    }

    var body: some View {
        List(selection: selectedItemID) {
            ForEach(items) { item in
                ClipboardItemRow(
                    item: item,
                    viewModel: viewModel
                )
                .tag(item.id)
                .contextMenu {
                    ContextMenuContent(item: item, viewModel: viewModel)
                }
                .listRowSeparator(.visible)
            }

            if items.count > 0 {
                LoadMoreButton {
                    viewModel.loadMore()
                }
                .padding(.top, 16)
            }
        }
        .listStyle(.plain)
    }
}

struct ClipboardItemRow: View {
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
    let item: ClipboardItem
    let viewModel: ClipboardViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Content type icon
            ContentTypeIcon(content: item.content)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                // Main content preview
                Text(item.content.displayText)
                    .font(.system(.body, design: .default))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Metadata row
                HStack(spacing: 8) {
                    // Source application
                    Label(item.source.applicationName ?? "Unknown", systemImage: "app")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Timestamp
                    Text(Self.relativeDateFormatter.localizedString(for: item.timestamps.createdAt, relativeTo: Date()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Status indicators
            HStack(spacing: 4) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }
}

struct ContentTypeIcon: View {
    let content: ClipboardContent
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
            .font(.system(size: 16))
    }

    private var iconName: String {
        switch content {
        case .text: return "doc.text"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .file: return "doc"
        case .link: return "link"
        case .code: return "curlybraces"
        case .color: return "paintpalette"
        case .snippet: return "note.text"
        case .multiple: return "doc.on.doc"
        }
    }

    private var iconColor: Color {
        switch content {
        case .text: return .primary
        case .richText: return colorScheme == .dark ? .blue : .primary
        case .image: return colorScheme == .dark ? .green : .primary
        case .file: return colorScheme == .dark ? .orange : .primary
        case .link: return colorScheme == .dark ? .blue : .primary
        case .code: return colorScheme == .dark ? .mint : .primary
        case .color: return colorScheme == .dark ? .pink : .primary
        case .snippet: return colorScheme == .dark ? .yellow : .primary
        case .multiple: return .secondary
        }
    }
}


struct ContextMenuContent: View {
    let item: ClipboardItem
    let viewModel: ClipboardViewModel

    var body: some View {
        Button("Copy Again") {
            viewModel.pasteItem(item)
        }

        Button(item.isPinned ? "Unpin" : "Pin") {
            viewModel.togglePin(for: item)
        }

        Button(item.isFavorite ? "Unfavorite" : "Favorite") {
            viewModel.toggleFavorite(for: item)
        }

        Divider()

        Menu("Transform") {
            ForEach(TransformAction.allCases, id: \.self) { transform in
                Button(transform.displayName) {
                    viewModel.pasteItem(item, transform: transform)
                }
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            viewModel.deleteItem(item)
        }
    }
}

struct LoadMoreButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                Image(systemName: "arrow.down")
                Text("Load More")
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}