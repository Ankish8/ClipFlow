import SwiftUI
import ClipFlowCore

struct ClipboardOverlayView: View {
    let viewModel: ClipboardViewModel
    @State private var selectedIndex: Int = 0
    @State private var selectedTagIds: Set<UUID> = []

    // Search state — raw text from the search field
    @State private var searchText = ""
    // Debounced text actually used for filtering (updated 80ms after last keystroke)
    @State private var debouncedSearch = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    // Default initializer creates its own viewModel (for standalone use)
    init() {
        let vm = ClipboardViewModel()
        vm.initialize()
        self.viewModel = vm
    }

    // Initializer that accepts a shared viewModel (for shared use)
    init(viewModel: ClipboardViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Derived display data
    // Computed directly from @Observable viewModel.items + @State filters.
    // SwiftUI auto-tracks all reads here — no onChange synchronisation needed.
    // Pinned items sort first; then newest-first (viewModel.items order).
    private var filteredItems: [ClipboardItem] {
        var items = viewModel.items

        if !selectedTagIds.isEmpty {
            items = items.filter { !$0.tagIds.isDisjoint(with: selectedTagIds) }
        }

        if !debouncedSearch.isEmpty {
            let q = debouncedSearch
            items = items.filter {
                $0.content.displayText.localizedCaseInsensitiveContains(q)
                    || ($0.source.applicationName?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }

        // Preserve newest-first ordering from viewModel.items and lift pinned items
        // with a linear-time stable partition instead of re-sorting every render.
        var pinnedItems: [ClipboardItem] = []
        var unpinnedItems: [ClipboardItem] = []
        pinnedItems.reserveCapacity(items.count)
        unpinnedItems.reserveCapacity(items.count)

        for item in items {
            if item.isPinned {
                pinnedItems.append(item)
            } else {
                unpinnedItems.append(item)
            }
        }

        return pinnedItems + unpinnedItems
    }

    var body: some View {
        overlayContent
    }

    @ViewBuilder
    private var overlayContent: some View {
        VStack(spacing: 0) {
            TagFilterBarView(
                viewModel: viewModel,
                selectedTagIds: $selectedTagIds,
                searchText: $searchText
            )
            .padding(.top, 10)

            Spacer().frame(height: 8)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 8) {
                        cardStack
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 252)
                .mask {
                    HStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 32)
                    }
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            Spacer().frame(height: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.clear }
        .overlayPanel(cornerRadius: 32)
        .onChange(of: searchText) {
            // Debounce: update debouncedSearch 80ms after last keystroke
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                debouncedSearch = searchText
            }
        }
        .onChange(of: selectedTagIds) { _, _ in
            let maxIndex = max(filteredItems.count - 1, 0)
            selectedIndex = min(selectedIndex, maxIndex)
        }
        .onChange(of: debouncedSearch) { _, _ in
            let maxIndex = max(filteredItems.count - 1, 0)
            selectedIndex = min(selectedIndex, maxIndex)
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Card Stack

    private var cardStack: some View {
        let items = Array(filteredItems.enumerated())
        return LazyHStack(spacing: 16) {
            if items.count <= 6 {
                Spacer().frame(minWidth: 0)
            }
            ForEach(items, id: \.element.id) { index, item in
                ClipboardCardView(
                    item: item,
                    index: index + 1,
                    isSelected: index == selectedIndex,
                    viewModel: viewModel
                )
                .id(item.id)
                .onTapGesture {
                    selectedIndex = index
                }
            }
            if items.count <= 6 {
                Spacer().frame(minWidth: 0)
            }
        }
    }

    private func selectAndPaste(_ item: ClipboardItem, index: Int) {
        selectedIndex = index
        viewModel.pasteItem(item)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
        }
    }

    func closeOverlay() {
        NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
    }

    // MARK: - Keyboard Navigation Methods

    func navigateLeft() {
        if selectedIndex > 0 { selectedIndex -= 1 }
    }

    func navigateRight() {
        let count = filteredItems.count
        if selectedIndex < count - 1 { selectedIndex += 1 }
    }

    func selectByNumber(_ number: Int) {
        let index = number - 1
        if index >= 0 && index < filteredItems.count {
            selectedIndex = index
        }
    }

    func pasteCurrentSelection() {
        let items = filteredItems
        guard selectedIndex < items.count else { return }
        selectAndPaste(items[selectedIndex], index: selectedIndex)
    }

    func deleteCurrentSelection() {
        let items = filteredItems
        guard selectedIndex < items.count else { return }
        viewModel.deleteItem(items[selectedIndex])
        if selectedIndex >= filteredItems.count && selectedIndex > 0 {
            selectedIndex -= 1
        }
    }
}

#Preview("Overlay – With Items") {
    let vm = ClipboardViewModel()
    let items: [ClipboardItem] = [
        ClipboardItem(
            content: .text(TextContent(plainText: "Hello, World! This is a sample clipboard entry.")),
            metadata: ItemMetadata(size: 48, hash: "a1"),
            source: ItemSource(applicationName: "Xcode")
        ),
        ClipboardItem(
            content: .text(TextContent(plainText: "func buildApp() -> some View { ContentView() }")),
            metadata: ItemMetadata(size: 46, hash: "b2"),
            source: ItemSource(applicationName: "Xcode")
        ),
        ClipboardItem(
            content: .link(LinkContent(url: URL(string: "https://developer.apple.com")!, title: "Apple Developer")),
            metadata: ItemMetadata(size: 30, hash: "c3"),
            source: ItemSource(applicationName: "Safari")
        ),
        ClipboardItem(
            content: .color(ColorContent(red: 0.2, green: 0.6, blue: 1.0)),
            metadata: ItemMetadata(size: 7, hash: "d4"),
            source: ItemSource(applicationName: "Figma")
        ),
    ]
    vm.items = items
    return ClipboardOverlayView(viewModel: vm)
        .frame(width: 780, height: 340)
        .background(Color.gray.opacity(0.2))
}

// Notification names
extension Notification.Name {
    static let hideClipboardOverlay = Notification.Name("hideClipboardOverlay")
    static let showClipboardOverlay = Notification.Name("showClipboardOverlay")
    static let deleteClipboardItem = Notification.Name("deleteClipboardItem")
    static let pinClipboardItem = Notification.Name("pinClipboardItem")
    static let startDragging = Notification.Name("startDragging")
    static let stopDragging = Notification.Name("stopDragging")
}

extension NSApplication {
    static let keyboardShortcutNotification = Notification.Name("keyboardShortcut")
}
