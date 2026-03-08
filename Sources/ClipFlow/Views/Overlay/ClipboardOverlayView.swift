import SwiftUI
import ClipFlowCore

struct ClipboardOverlayView: View {
    let viewModel: ClipboardViewModel
    // ID-based selection — stable across pagination/filtering
    @State private var focusedItemId: UUID?
    @State private var selectedItemIds: Set<UUID> = []
    @State private var selectionAnchorId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    @State private var selectedContentType: String? = nil  // nil = all types

    // Quick Look state
    @State private var showQuickLook = false

    // Search state — raw text from the search field
    @State private var searchText = ""
    // Debounced text actually used for filtering (updated 80ms after last keystroke)
    @State private var debouncedSearch = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    // Coalesces rapid filter changes into a single DB query
    @State private var filterCoalesceTask: Task<Void, Never>?

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

    // MARK: - Selection Helpers (ID-based)

    /// Compute display index of focused item.
    private var focusedIndex: Int {
        guard let fid = focusedItemId else { return 0 }
        return viewModel.items.firstIndex(where: { $0.id == fid }) ?? 0
    }

    /// Resolve content types for the selected filter chip.
    private var resolvedContentTypes: [String]? {
        guard let ct = selectedContentType else { return nil }
        let matchTypes = ContentTypeFilter.filters.first { $0.id == ct }?.matchTypes
        return matchTypes.map { Array($0) }
    }

    /// Push current UI filter state to ViewModel.
    /// Filters are **exclusive**: content type OR tag, not both.
    /// Coalesces rapid changes (e.g., toggleTag clears contentType + sets tagIds = 2 onChange fires)
    /// into a single DB query after a microtask yield.
    private func pushFilterToViewModel() {
        filterCoalesceTask?.cancel()
        filterCoalesceTask = Task { @MainActor in
            // Yield to let SwiftUI batch all state changes in this event cycle
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            viewModel.applyFilter(
                tagIds: selectedTagIds.isEmpty ? nil : selectedTagIds,
                contentTypes: selectedTagIds.isEmpty ? resolvedContentTypes : nil,
                searchQuery: debouncedSearch.isEmpty ? nil : debouncedSearch
            )
        }
    }

    var body: some View {
        overlayContent
    }

    @ViewBuilder
    private var overlayContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TagFilterBarView(
                    viewModel: viewModel,
                    selectedTagIds: $selectedTagIds,
                    selectedContentType: $selectedContentType,
                    searchText: $searchText
                )

                // Settings gear — top-right corner of overlay
                Button {
                    // Hide overlay first, then open settings after a brief
                    // delay so the activation policy switch doesn't race.
                    NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        SettingsWindowController.shared.showSettings()
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
                .padding(.trailing, 16)
            }
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
                .onChange(of: focusedItemId) { _, newId in
                    if let newId {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
            }

            Spacer().frame(height: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.clear }
        .overlayPanel(cornerRadius: 32)
        .onChange(of: focusedItemId) { _, _ in
            // Update Quick Look panel with new selection
            if showQuickLook, let fid = focusedItemId,
               let item = viewModel.items.first(where: { $0.id == fid }) {
                NotificationCenter.default.post(
                    name: .showQuickLookPanel,
                    object: nil,
                    userInfo: ["item": item]
                )
            }
        }
        .onChange(of: searchText) {
            // Debounce: update debouncedSearch 80ms after last keystroke
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                debouncedSearch = searchText
            }
        }
        .onAppear {
            // Select first item on appear
            focusedItemId = viewModel.items.first?.id
            if let fid = focusedItemId {
                selectedItemIds = [fid]
                selectionAnchorId = fid
            }
        }
        .onChange(of: viewModel.items) { _, newItems in
            // If focused item no longer exists, clamp to first
            if let fid = focusedItemId, !newItems.contains(where: { $0.id == fid }) {
                focusedItemId = newItems.first?.id
                if let fid = focusedItemId {
                    selectedItemIds = [fid]
                    selectionAnchorId = fid
                }
            }
            // If no selection, select first
            if focusedItemId == nil, let first = newItems.first {
                focusedItemId = first.id
                selectedItemIds = [first.id]
                selectionAnchorId = first.id
            }
        }
        .onChange(of: selectedTagIds) { _, _ in
            pushFilterToViewModel()
        }
        .onChange(of: debouncedSearch) { _, _ in
            pushFilterToViewModel()
        }
        .onChange(of: selectedContentType) { _, _ in
            pushFilterToViewModel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateOverlayLeft)) { _ in
            navigateLeft()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateOverlayRight)) { _ in
            navigateRight()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateOverlayLeftExtend)) { _ in
            let idx = focusedIndex
            if idx > 0 {
                let newItem = viewModel.items[idx - 1]
                focusedItemId = newItem.id
                selectedItemIds = idRangeSet(from: selectionAnchorId, to: newItem.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateOverlayRightExtend)) { _ in
            let idx = focusedIndex
            if idx < viewModel.items.count - 1 {
                let newItem = viewModel.items[idx + 1]
                focusedItemId = newItem.id
                selectedItemIds = idRangeSet(from: selectionAnchorId, to: newItem.id)
                // Trigger load more if near end
                if idx + 1 >= viewModel.items.count - 3 {
                    viewModel.loadMore()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cardTappedWithShift)) { note in
            if let index = note.userInfo?["index"] as? Int,
               index < viewModel.items.count {
                let item = viewModel.items[index]
                focusedItemId = item.id
                selectedItemIds = idRangeSet(from: selectionAnchorId, to: item.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleQuickLook)) { _ in
            guard let fid = focusedItemId,
                  let item = viewModel.items.first(where: { $0.id == fid }) else { return }
            showQuickLook.toggle()
            if showQuickLook {
                NotificationCenter.default.post(
                    name: .showQuickLookPanel,
                    object: nil,
                    userInfo: ["item": item]
                )
            } else {
                NotificationCenter.default.post(name: .hideQuickLookPanel, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteOverlaySelection)) { _ in
            pasteCurrentSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteOverlaySelectionPlain)) { _ in
            pasteCurrentSelectionPlain()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteOverlaySelection)) { _ in
            deleteCurrentSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectAllOverlayItems)) { _ in
            selectAllItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePinOverlaySelection)) { _ in
            togglePinCurrentSelection()
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Card Stack

    private var cardStack: some View {
        let allItems = viewModel.items
        let indexedItems = Array(allItems.enumerated())
        let selectedItemsList = allItems.filter { selectedItemIds.contains($0.id) }
        return LazyHStack(spacing: 16) {
            if allItems.count <= 6 {
                Spacer().frame(minWidth: 0)
            }
            ForEach(indexedItems, id: \.element.id) { index, item in
                ClipboardCardView(
                    item: item,
                    index: index + 1,
                    isSelected: selectedItemIds.contains(item.id),
                    viewModel: viewModel,
                    onSelect: {
                        focusedItemId = item.id
                        selectionAnchorId = item.id
                        selectedItemIds = [item.id]
                    },
                    onShiftSelect: { _ in
                        focusedItemId = item.id
                        selectedItemIds = idRangeSet(from: selectionAnchorId, to: item.id)
                    },
                    selectedItems: selectedItemsList
                )
                .id(item.id)
            }
            // Infinite scroll sentinel
            if viewModel.hasMore {
                Color.clear.frame(width: 1).onAppear {
                    viewModel.loadMore()
                }
            }
            if allItems.count <= 6 {
                Spacer().frame(minWidth: 0)
            }
        }
    }

    private func selectAndPaste(_ item: ClipboardItem) {
        focusedItemId = item.id
        selectedItemIds = [item.id]
        // CRITICAL: Hide overlay FIRST so focus returns to the target app,
        // then paste after focus restoration completes. Otherwise the
        // simulated ⌘V keystroke lands on the overlay panel itself.
        NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            viewModel.pasteItem(item)
        }
    }

    func closeOverlay() {
        NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
    }

    /// Double-Escape pattern: first Escape dismisses Quick Look panel, second closes overlay.
    func dismissQuickLookOrClose() {
        if showQuickLook {
            showQuickLook = false
            NotificationCenter.default.post(name: .hideQuickLookPanel, object: nil)
        } else {
            closeOverlay()
        }
    }

    /// Build a set of item IDs between two anchor IDs (inclusive range).
    private func idRangeSet(from anchorId: UUID?, to targetId: UUID) -> Set<UUID> {
        let items = viewModel.items
        guard let aid = anchorId,
              let anchorIdx = items.firstIndex(where: { $0.id == aid }),
              let targetIdx = items.firstIndex(where: { $0.id == targetId }) else {
            return [targetId]
        }
        let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
        return Set(items[range].map(\.id))
    }

    // MARK: - Keyboard Navigation Methods

    func navigateLeft() {
        let idx = focusedIndex
        if idx > 0 {
            let item = viewModel.items[idx - 1]
            focusedItemId = item.id
            selectionAnchorId = item.id
            selectedItemIds = [item.id]
        }
    }

    func navigateRight() {
        let items = viewModel.items
        let idx = focusedIndex
        if idx < items.count - 1 {
            let item = items[idx + 1]
            focusedItemId = item.id
            selectionAnchorId = item.id
            selectedItemIds = [item.id]
            // Trigger load more if near end
            if idx + 1 >= items.count - 3 {
                viewModel.loadMore()
            }
        }
    }

    func selectByNumber(_ number: Int) {
        let index = number - 1
        let items = viewModel.items
        if index >= 0 && index < items.count {
            let item = items[index]
            focusedItemId = item.id
            selectionAnchorId = item.id
            selectedItemIds = [item.id]
        }
    }

    func pasteCurrentSelection() {
        let items = viewModel.items
        if selectedItemIds.count > 1 {
            let selectedItems = items.filter { selectedItemIds.contains($0.id) }
            guard !selectedItems.isEmpty else { return }
            // Hide overlay first, then paste after focus restores
            NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                viewModel.pasteMultipleItems(selectedItems)
            }
        } else if let fid = focusedItemId, let item = items.first(where: { $0.id == fid }) {
            selectAndPaste(item)
        }
    }

    /// Paste current selection with formatting stripped (Shift+Return shortcut).
    func pasteCurrentSelectionPlain() {
        guard let fid = focusedItemId,
              let item = viewModel.items.first(where: { $0.id == fid }) else { return }
        NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            viewModel.pasteItem(item, transform: .removeFormatting)
        }
    }

    func toggleQuickLook() {
        showQuickLook.toggle()
    }

    func selectAllItems() {
        let items = viewModel.items
        guard !items.isEmpty else { return }
        selectedItemIds = Set(items.map(\.id))
        // Keep focus on current item, or first if none
        if focusedItemId == nil {
            focusedItemId = items.first?.id
        }
    }

    func togglePinCurrentSelection() {
        guard let fid = focusedItemId,
              let item = viewModel.items.first(where: { $0.id == fid }) else { return }
        viewModel.togglePin(for: item)
    }

    func editCurrentSelection() {
        guard let fid = focusedItemId else { return }
        NotificationCenter.default.post(
            name: .editClipboardItem,
            object: nil,
            userInfo: ["itemId": fid]
        )
    }

    func deleteCurrentSelection() {
        let items = viewModel.items
        if selectedItemIds.count > 1 {
            for id in selectedItemIds {
                if let item = items.first(where: { $0.id == id }) {
                    viewModel.deleteItem(item)
                }
            }
            // Select first remaining item
            focusedItemId = viewModel.items.first?.id
            if let fid = focusedItemId {
                selectedItemIds = [fid]
                selectionAnchorId = fid
            } else {
                selectedItemIds = []
            }
        } else if let fid = focusedItemId, let item = items.first(where: { $0.id == fid }) {
            let idx = focusedIndex
            viewModel.deleteItem(item)
            // Select next item or previous
            let newItems = viewModel.items
            let newIdx = min(idx, max(newItems.count - 1, 0))
            if newIdx < newItems.count {
                let newItem = newItems[newIdx]
                focusedItemId = newItem.id
                selectedItemIds = [newItem.id]
                selectionAnchorId = newItem.id
            } else {
                focusedItemId = nil
                selectedItemIds = []
            }
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
    static let editClipboardItem = Notification.Name("editClipboardItem")
    static let toggleQuickLook = Notification.Name("toggleQuickLook")
    static let showQuickLookPanel = Notification.Name("showQuickLookPanel")
    static let hideQuickLookPanel = Notification.Name("hideQuickLookPanel")
    static let navigateOverlayLeft = Notification.Name("navigateOverlayLeft")
    static let navigateOverlayRight = Notification.Name("navigateOverlayRight")
    static let navigateOverlayLeftExtend = Notification.Name("navigateOverlayLeftExtend")
    static let navigateOverlayRightExtend = Notification.Name("navigateOverlayRightExtend")
    static let cardTappedWithShift = Notification.Name("cardTappedWithShift")
    static let pasteOverlaySelection = Notification.Name("pasteOverlaySelection")
    static let pasteOverlaySelectionPlain = Notification.Name("pasteOverlaySelectionPlain")
    static let deleteOverlaySelection = Notification.Name("deleteOverlaySelection")
    static let selectAllOverlayItems = Notification.Name("selectAllOverlayItems")
    static let togglePinOverlaySelection = Notification.Name("togglePinOverlaySelection")
}

extension NSApplication {
    static let keyboardShortcutNotification = Notification.Name("keyboardShortcut")
}
