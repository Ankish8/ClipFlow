import SwiftUI
import ClipFlowCore

struct ClipboardOverlayView: View {
    let viewModel: ClipboardViewModel
    @State private var selectedIndex: Int = 0
    @State private var selectionAnchor: Int = 0
    @State private var selectedIndices: Set<Int> = [0]
    @State private var selectedTagIds: Set<UUID> = []

    // Quick Look state
    @State private var showQuickLook = false

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
            HStack(spacing: 0) {
                TagFilterBarView(
                    viewModel: viewModel,
                    selectedTagIds: $selectedTagIds,
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
        .onChange(of: selectedIndex) { _, newIndex in
            // Update Quick Look panel with new selection instead of dismissing
            if showQuickLook, newIndex < filteredItems.count {
                NotificationCenter.default.post(
                    name: .showQuickLookPanel,
                    object: nil,
                    userInfo: ["item": filteredItems[newIndex]]
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
        .onChange(of: selectedTagIds) { _, newTagIds in
            viewModel.loadItemsByTag(tagIds: newTagIds)
            let maxIndex = max(filteredItems.count - 1, 0)
            selectedIndex = min(selectedIndex, maxIndex)
            selectionAnchor = selectedIndex
            selectedIndices = [selectedIndex]
        }
        .onChange(of: debouncedSearch) { _, _ in
            let maxIndex = max(filteredItems.count - 1, 0)
            selectedIndex = min(selectedIndex, maxIndex)
            selectionAnchor = selectedIndex
            selectedIndices = [selectedIndex]
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateOverlayLeft)) { _ in
            if selectedIndex > 0 {
                selectedIndex -= 1
                selectionAnchor = selectedIndex
                selectedIndices = [selectedIndex]
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateOverlayRight)) { _ in
            if selectedIndex < filteredItems.count - 1 {
                selectedIndex += 1
                selectionAnchor = selectedIndex
                selectedIndices = [selectedIndex]
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateOverlayLeftExtend)) { _ in
            if selectedIndex > 0 {
                selectedIndex -= 1
                selectedIndices = rangeSet(from: selectionAnchor, to: selectedIndex)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateOverlayRightExtend)) { _ in
            if selectedIndex < filteredItems.count - 1 {
                selectedIndex += 1
                selectedIndices = rangeSet(from: selectionAnchor, to: selectedIndex)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cardTappedWithShift)) { note in
            if let index = note.userInfo?["index"] as? Int {
                selectedIndex = index
                selectedIndices = rangeSet(from: selectionAnchor, to: index)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleQuickLook)) { _ in
            let items = filteredItems
            guard selectedIndex < items.count else { return }
            showQuickLook.toggle()
            if showQuickLook {
                NotificationCenter.default.post(
                    name: .showQuickLookPanel,
                    object: nil,
                    userInfo: ["item": items[selectedIndex]]
                )
            } else {
                NotificationCenter.default.post(name: .hideQuickLookPanel, object: nil)
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Card Stack

    private var cardStack: some View {
        let items = Array(filteredItems.enumerated())
        let selectedItemsList = selectedIndices.sorted().compactMap { idx in
            idx < filteredItems.count ? filteredItems[idx] : nil
        }
        return LazyHStack(spacing: 16) {
            if items.count <= 6 {
                Spacer().frame(minWidth: 0)
            }
            ForEach(items, id: \.element.id) { index, item in
                ClipboardCardView(
                    item: item,
                    index: index + 1,
                    isSelected: selectedIndices.contains(index),
                    viewModel: viewModel,
                    onSelect: {
                        selectedIndex = index
                        selectionAnchor = index
                        selectedIndices = [index]
                    },
                    onShiftSelect: { shiftIndex in
                        selectedIndex = shiftIndex
                        selectedIndices = rangeSet(from: selectionAnchor, to: shiftIndex)
                    },
                    selectedItems: selectedItemsList
                )
                .id(item.id)
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

    /// Double-Escape pattern: first Escape dismisses Quick Look panel, second closes overlay.
    func dismissQuickLookOrClose() {
        if showQuickLook {
            showQuickLook = false
            NotificationCenter.default.post(name: .hideQuickLookPanel, object: nil)
        } else {
            closeOverlay()
        }
    }

    // MARK: - Selection Helpers

    private func rangeSet(from a: Int, to b: Int) -> Set<Int> {
        Set(min(a, b)...max(a, b))
    }

    // MARK: - Keyboard Navigation Methods

    func navigateLeft() {
        if selectedIndex > 0 {
            selectedIndex -= 1
            selectionAnchor = selectedIndex
            selectedIndices = [selectedIndex]
        }
    }

    func navigateRight() {
        let count = filteredItems.count
        if selectedIndex < count - 1 {
            selectedIndex += 1
            selectionAnchor = selectedIndex
            selectedIndices = [selectedIndex]
        }
    }

    func selectByNumber(_ number: Int) {
        let index = number - 1
        if index >= 0 && index < filteredItems.count {
            selectedIndex = index
            selectionAnchor = index
            selectedIndices = [index]
        }
    }

    func pasteCurrentSelection() {
        let items = filteredItems
        if selectedIndices.count > 1 {
            // Multi-paste: writes images as temp file URLs (for Finder),
            // text as concatenated string, then simulates ⌘V.
            let selectedItems = selectedIndices.sorted().compactMap { idx in
                idx < items.count ? items[idx] : nil
            }
            guard !selectedItems.isEmpty else { return }
            viewModel.pasteMultipleItems(selectedItems)
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
            }
        } else {
            guard selectedIndex < items.count else { return }
            selectAndPaste(items[selectedIndex], index: selectedIndex)
        }
    }

    /// Paste current selection with formatting stripped (Shift+Return shortcut).
    func pasteCurrentSelectionPlain() {
        let items = filteredItems
        guard selectedIndex < items.count else { return }
        let item = items[selectedIndex]
        viewModel.pasteItem(item, transform: .removeFormatting)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
        }
    }

    func toggleQuickLook() {
        showQuickLook.toggle()
    }

    func editCurrentSelection() {
        let items = filteredItems
        guard selectedIndex < items.count else { return }
        let item = items[selectedIndex]
        // Post notification that triggers the edit window for this item
        NotificationCenter.default.post(
            name: .editClipboardItem,
            object: nil,
            userInfo: ["itemId": item.id]
        )
    }

    func deleteCurrentSelection() {
        let items = filteredItems
        if selectedIndices.count > 1 {
            // Delete all selected items (reverse order to preserve indices)
            for idx in selectedIndices.sorted().reversed() {
                guard idx < items.count else { continue }
                viewModel.deleteItem(items[idx])
            }
            let newIndex = max(0, (selectedIndices.min() ?? 0))
            selectedIndex = min(newIndex, max(filteredItems.count - 1, 0))
            selectionAnchor = selectedIndex
            selectedIndices = [selectedIndex]
        } else {
            guard selectedIndex < items.count else { return }
            viewModel.deleteItem(items[selectedIndex])
            if selectedIndex >= filteredItems.count && selectedIndex > 0 {
                selectedIndex -= 1
            }
            selectionAnchor = selectedIndex
            selectedIndices = [selectedIndex]
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
}

extension NSApplication {
    static let keyboardShortcutNotification = Notification.Name("keyboardShortcut")
}
