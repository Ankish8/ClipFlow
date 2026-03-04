import SwiftUI
import ClipFlowCore

struct ClipboardOverlayView: View {
    let viewModel: ClipboardViewModel
    @State private var selectedIndex: Int = 0
    @State private var selectedTagIds: Set<UUID> = []

    // Search state - managed here for keyboard capture
    @State private var isSearchExpanded = false
    @State private var searchText = ""

    // PERFORMANCE: Cache filtered items instead of recomputing on every render
    @State private var filteredItems: [ClipboardItem] = []

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

    // PERFORMANCE: Compute filtered items once and cache the result
    private func updateFilteredItems() {
        var items = viewModel.items

        // Apply tag filtering
        if !selectedTagIds.isEmpty {
            items = items.filter { item in
                !item.tagIds.intersection(selectedTagIds).isEmpty
            }
        }

        filteredItems = items
    }

    var body: some View {
        // TimelineView keeps SwiftUI's render pipeline ticking every display frame on macOS 26,
        // which forces .glassEffect to re-sample behind-window content continuously
        // (fixes the "glass gets stuck when scrolling" issue).
        if #available(macOS 26, *) {
            TimelineView(.animation) { _ in
                overlayContent
            }
        } else {
            overlayContent
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        VStack(spacing: 0) {
            // Horizontal tag filter bar
            TagFilterBarView(
                viewModel: viewModel,
                selectedTagIds: $selectedTagIds,
                isSearchExpanded: $isSearchExpanded,
                searchText: $searchText
            )
            .padding(.top, 10)

            Spacer().frame(height: 8)

            // Main cards container - full width
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    cardStack
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 252)
                .onChange(of: selectedIndex) { newIndex in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            Spacer().frame(height: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if #available(macOS 26, *) { Color.clear } else { overlayBackground }
        }
        .overlayPanel(cornerRadius: 32)
        .onAppear {
            updateFilteredItems()
        }
        .onChange(of: selectedTagIds) {
            updateFilteredItems()
        }
        .onChange(of: viewModel.items) {
            updateFilteredItems()
        }
        .focusable()
        .onKeyPress { press in
            // Auto-expand search when user starts typing
            if !isSearchExpanded && press.characters.count == 1 && !press.characters.isEmpty {
                let char = press.characters
                if char.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil
                    || char.rangeOfCharacter(from: CharacterSet.punctuationCharacters) != nil
                    || char == " " {
                    isSearchExpanded = true
                    searchText = char
                    return .handled
                }
            }
            return .ignored
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var overlayBackground: some View {
        VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            .ignoresSafeArea()
    }

    // MARK: - Card Stack (extracted for GlassEffectContainer wrapping)

    @ViewBuilder
    private var cardStack: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 16) {
                cardStackContent
            }
        } else {
            cardStackContent
        }
    }

    private var cardStackContent: some View {
        LazyHStack(spacing: 16) {
            if filteredItems.count <= 6 {
                Spacer().frame(minWidth: 0)
            }
            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
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
            if filteredItems.count <= 6 {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
        }
    }

    private func handleKeyboardInput() {
        // Called from the window's keyDown events
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

// Visual effect view for blur
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        // Mask the blur layer itself so it respects rounded corners
        view.wantsLayer = true
        view.layer?.cornerRadius = 32
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
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
