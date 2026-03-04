import SwiftUI
import ClipFlowCore

struct ClipboardOverlayView: View {
    let viewModel: ClipboardViewModel
    @State private var selectedIndex: Int = 0
    @State private var selectedTagIds: Set<UUID> = []

    // Search state
    @State private var searchText = ""

    // PERFORMANCE: Pre-sorted base (pinned first, then recency-order).
    // Rebuilt only when viewModel.items changes — NOT on every tag/search change.
    @State private var sortedBaseItems: [ClipboardItem] = []

    // PERFORMANCE: Cache filtered items instead of recomputing on every render
    @State private var filteredItems: [ClipboardItem] = []
    // PERFORMANCE: Avoid Array(enumerated()) allocation on every render
    @State private var enumeratedFilteredItems: [(offset: Int, element: ClipboardItem)] = []

    // Debounce: cancel previous search task before starting a new one
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

    // PERFORMANCE: Sort once when items change (O(n log n)), not on every tag switch.
    // viewModel.items are newest-first; pinned items float to front.
    private func rebuildSortedBase() {
        sortedBaseItems = viewModel.items.sorted { $0.isPinned && !$1.isPinned }
    }

    // PERFORMANCE: Filter from pre-sorted base — O(n) only, no sort cost.
    // Called on every tag/search change; sorting is handled by rebuildSortedBase().
    private func updateFilteredItems() {
        var items = sortedBaseItems

        // Apply tag filtering — isDisjoint avoids allocating an intersection Set
        if !selectedTagIds.isEmpty {
            items = items.filter { !$0.tagIds.isDisjoint(with: selectedTagIds) }
        }

        // Apply in-memory text filter — instant, no DB hit
        // Enter key triggers the deep DB search via ExpandableSearchBar.onSubmit
        if !searchText.isEmpty {
            let query = searchText
            items = items.filter { item in
                item.content.displayText.localizedCaseInsensitiveContains(query)
                    || (item.source.applicationName?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        filteredItems = items
        enumeratedFilteredItems = Array(items.enumerated())
    }

    var body: some View {
        // NSGlassEffectView live-compositing is kept alive by makeKeyAndOrderFront(nil)
        // on the NSPanel — no TimelineView needed. See MEMORY.md: Liquid Glass Overlay.
        overlayContent
    }

    @ViewBuilder
    private var overlayContent: some View {
        VStack(spacing: 0) {
            // Horizontal tag filter bar (search field always visible inside)
            TagFilterBarView(
                viewModel: viewModel,
                selectedTagIds: $selectedTagIds,
                searchText: $searchText
            )
            .padding(.top, 10)

            Spacer().frame(height: 8)

            // Main cards container - wrapped in GlassEffectContainer for morphing
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
        .onAppear {
            rebuildSortedBase()
            updateFilteredItems()
        }
        .onChange(of: selectedTagIds) {
            // Tag changes are instant — filter from already-sorted base
            updateFilteredItems()
        }
        .onChange(of: viewModel.items) {
            // Items changed — re-sort once, then re-filter
            rebuildSortedBase()
            updateFilteredItems()
        }
        .onChange(of: searchText) {
            // Debounce: wait 80ms after last keystroke before filtering
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                updateFilteredItems()
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Card Stack

    private var cardStack: some View {
        cardStackContent
    }

    private var cardStackContent: some View {
        LazyHStack(spacing: 16) {
            if enumeratedFilteredItems.count <= 6 {
                Spacer().frame(minWidth: 0)
            }
            ForEach(enumeratedFilteredItems, id: \.element.id) { index, item in
                ClipboardCardView(
                    item: item,
                    index: index + 1,
                    isSelected: index == selectedIndex,
                    viewModel: viewModel
                )
                .id(item.id)
                .onTapGesture {
                    selectItem(index: index)
                }
            }
            if enumeratedFilteredItems.count <= 6 {
                Spacer().frame(minWidth: 0)
            }
        }
    }

    private func selectItem(index: Int) {
        selectedIndex = index
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
        if selectedIndex < filteredItems.count - 1 { selectedIndex += 1 }
    }

    func selectByNumber(_ number: Int) {
        let index = number - 1
        if index >= 0 && index < filteredItems.count {
            selectedIndex = index
        }
    }

    func pasteCurrentSelection() {
        guard selectedIndex < filteredItems.count else { return }
        selectAndPaste(filteredItems[selectedIndex], index: selectedIndex)
    }

    func deleteCurrentSelection() {
        guard selectedIndex < filteredItems.count else { return }
        viewModel.deleteItem(filteredItems[selectedIndex])
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
