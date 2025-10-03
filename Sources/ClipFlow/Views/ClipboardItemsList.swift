import SwiftUI
import ClipFlowCore
import ClipFlowAPI

struct ClipboardItemsList: View {
    let items: [ClipboardItem]
    @Binding var selectedItem: ClipboardItem?
    let viewModel: ClipboardViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(items) { item in
                    ClipboardItemRow(
                        item: item,
                        isSelected: selectedItem?.id == item.id,
                        viewModel: viewModel
                    )
                    .onTapGesture {
                        selectedItem = item
                    }
                    .contextMenu {
                        ContextMenuContent(item: item, viewModel: viewModel)
                    }
                }

                if items.count > 0 {
                    LoadMoreButton {
                        viewModel.loadMore()
                    }
                    .padding(.top, 16)
                }
            }
            .padding(.vertical, 4)
        }
        .background(.regularMaterial)
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
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
                        .foregroundColor(.secondary)

                    Spacer()

                    // Timestamp
                    Text(RelativeDateTimeFormatter().localizedString(for: item.timestamps.createdAt, relativeTo: Date()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

            }

            Spacer()

            // Status indicators
            VStack(spacing: 4) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                // Security features removed for v1
                // if item.security.isEncrypted { ... }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.customAccent.opacity(0.2) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

struct ContentTypeIcon: View {
    let content: ClipboardContent
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Image(systemName: iconName)
            .foregroundColor(iconColor)
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
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }
}