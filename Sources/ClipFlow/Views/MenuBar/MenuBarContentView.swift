import SwiftUI
import ClipFlowCore

// MARK: - Menu Bar Content View
/// Modern SwiftUI interface embedded in AppKit popover for optimal UX
/// Implements keyboard-first navigation with sub-100ms response times

struct MenuBarContentView: View {
    @ObservedObject var manager: MenuBarManager
    @State private var selectedIndex = 0
    @State private var searchResults: [ClipboardItem] = []
    @State private var isSearching = false
    @FocusState private var isSearchFocused: Bool

    private let cardHeight: CGFloat = 60
    private let maxVisibleItems = 8

    var displayItems: [ClipboardItem] {
        isSearching ? searchResults : manager.recentItems
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            searchBarView
            contentView
            footerView
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            isSearchFocused = true
        }
        .onKeyDown { keyCode in
            handleKeyDown(keyCode)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundColor(.accentColor)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("ClipFlow")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("\(displayItems.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Quick actions
            HStack(spacing: 8) {
                Button(action: { manager.overlayManager.showOverlay() }) {
                    Image(systemName: "rectangle.3.offgrid")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("Show Overlay (⌥⌘V)")

                Button(action: { showPreferences() }) {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("Preferences")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Search Bar

    private var searchBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))

            TextField("Search clipboard history...", text: $manager.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onChange(of: manager.searchText) { newValue in
                    performSearch(query: newValue)
                }

            if !manager.searchText.isEmpty {
                Button(action: clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    private var contentView: some View {
        ScrollView {
            ScrollViewReader { proxy in
                LazyVStack(spacing: 1) {
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        ClipboardItemCard(
                            item: item,
                            index: index + 1,
                            isSelected: index == selectedIndex,
                            onSelect: { selectItem(at: index) },
                            onPaste: { pasteItem(item) },
                            onDelete: { deleteItem(item) }
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(index == selectedIndex ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .onChange(of: selectedIndex) { newIndex in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: CGFloat(maxVisibleItems) * cardHeight)
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 8) {
            Divider()

            HStack {
                Text("⌥⌘V")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlColor))
                    .cornerRadius(4)

                Text("Overlay")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("↑↓ Navigate • ⏎ Paste • ⌫ Delete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Actions

    private func selectItem(at index: Int) {
        selectedIndex = index
    }

    private func pasteItem(_ item: ClipboardItem) {
        manager.pasteSelectedItem(item)
    }

    private func deleteItem(_ item: ClipboardItem) {
        manager.deleteItem(item)

        // Adjust selection if needed
        if selectedIndex >= displayItems.count && selectedIndex > 0 {
            selectedIndex = displayItems.count - 1
        }
    }

    private func performSearch(query: String) {
        if query.isEmpty {
            isSearching = false
            searchResults = []
            selectedIndex = 0
            return
        }

        isSearching = true
        selectedIndex = 0

        Task {
            let results = await manager.searchItems(query: query)
            await MainActor.run {
                searchResults = results
            }
        }
    }

    private func clearSearch() {
        manager.searchText = ""
        isSearching = false
        searchResults = []
        selectedIndex = 0
        isSearchFocused = true
    }

    private func showPreferences() {
        // Would open preferences window
        print("Show preferences")
    }

    // MARK: - Keyboard Navigation

    private func handleKeyDown(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 125: // Down arrow
            moveSelection(by: 1)
            return true

        case 126: // Up arrow
            moveSelection(by: -1)
            return true

        case 36: // Return/Enter
            if !displayItems.isEmpty {
                pasteItem(displayItems[selectedIndex])
                return true
            }

        case 51, 117: // Delete/Backspace
            if !displayItems.isEmpty && !isSearchFocused {
                deleteItem(displayItems[selectedIndex])
                return true
            }

        case 53: // Escape
            if isSearching && !manager.searchText.isEmpty {
                clearSearch()
            } else {
                manager.hidePopover()
            }
            return true

        case 18...26: // Number keys 1-9
            let number = Int(keyCode) - 17
            if number >= 1 && number <= displayItems.count {
                selectedIndex = number - 1
                pasteItem(displayItems[selectedIndex])
                return true
            }

        default:
            break
        }

        return false
    }

    private func moveSelection(by offset: Int) {
        let newIndex = selectedIndex + offset
        if newIndex >= 0 && newIndex < displayItems.count {
            selectedIndex = newIndex
        }
    }
}

// MARK: - Clipboard Item Card

private struct ClipboardItemCard: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Index indicator
            Text("\(index)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 20)

            // Content icon
            contentIcon
                .frame(width: 24, height: 24)
                .foregroundColor(isSelected ? .accentColor : .primary)

            // Content preview
            VStack(alignment: .leading, spacing: 2) {
                Text(item.content.displayText)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                HStack {
                    Text(item.content.contentType.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(formatDate(item.timestamps.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions (visible on hover/selection)
            if isSelected {
                HStack(spacing: 4) {
                    Button(action: onPaste) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Paste")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onPaste()
        }
    }

    @ViewBuilder
    private var contentIcon: some View {
        switch item.content {
        case .text:
            Image(systemName: "textformat")
        case .richText:
            Image(systemName: "textformat.alt")
        case .image:
            Image(systemName: "photo")
        case .file:
            Image(systemName: "doc")
        case .link:
            Image(systemName: "link")
        case .code:
            Image(systemName: "curlybraces")
        case .color:
            Image(systemName: "paintpalette")
        case .snippet:
            Image(systemName: "text.snippet")
        case .multiple:
            Image(systemName: "square.stack")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Key Down Modifier

private struct KeyDownViewModifier: ViewModifier {
    let handler: (UInt16) -> Bool

    func body(content: Content) -> some View {
        content
            .background(KeyDownView(handler: handler))
    }
}

private struct KeyDownView: NSViewRepresentable {
    let handler: (UInt16) -> Bool

    func makeNSView(context: Context) -> NSView {
        KeyDownNSView(handler: handler)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class KeyDownNSView: NSView {
    let handler: (UInt16) -> Bool

    init(handler: @escaping (UInt16) -> Bool) {
        self.handler = handler
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !handler(event.keyCode) {
            super.keyDown(with: event)
        }
    }
}

extension View {
    func onKeyDown(perform handler: @escaping (UInt16) -> Bool) -> some View {
        modifier(KeyDownViewModifier(handler: handler))
    }
}