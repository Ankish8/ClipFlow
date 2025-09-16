import SwiftUI
import ClipFlowCore

struct ClipboardOverlayView: View {
    @StateObject private var viewModel = ClipboardViewModel()
    @State private var selectedIndex: Int = 0
    @State private var searchText = ""
    @State private var selectedFilter: ContentFilter = .all
    @State private var isSearchExpanded = false

    enum ContentFilter: String, CaseIterable {
        case all = "All"
        case text = "Text"
        case images = "Images"
        case files = "Files"
        case links = "Links"
        case colors = "Colors"

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .text: return "doc.text"
            case .images: return "photo"
            case .files: return "doc"
            case .links: return "link"
            case .colors: return "paintpalette"
            }
        }
    }

    var filteredItems: [ClipboardItem] {
        var items = viewModel.items

        // Apply enhanced search filtering
        if !searchText.isEmpty {
            items = items.filter { item in
                fuzzySearch(item: item, query: searchText)
            }
        }

        // Apply content type filtering
        if selectedFilter != .all {
            items = items.filter { item in
                matches(item.content, filter: selectedFilter)
            }
        }

        return items
    }

    private func fuzzySearch(item: ClipboardItem, query: String) -> Bool {
        let lowercaseQuery = query.lowercased()

        // Search in main content
        let contentText = item.content.displayText.lowercased()
        if contentText.contains(lowercaseQuery) {
            return true
        }

        // Search in source app name
        if let appName = item.source.applicationName?.lowercased(),
           appName.contains(lowercaseQuery) {
            return true
        }

        // Search in file names for file content
        if case .file(let fileContent) = item.content {
            if fileContent.fileName.lowercased().contains(lowercaseQuery) {
                return true
            }
        }

        // Search in URL domains for links
        if case .link(let linkContent) = item.content {
            if let host = linkContent.url.host?.lowercased(),
               host.contains(lowercaseQuery) {
                return true
            }
        }

        // Fuzzy matching - check if query characters appear in order
        return fuzzyMatch(text: contentText, query: lowercaseQuery)
    }

    private func fuzzyMatch(text: String, query: String) -> Bool {
        let textChars = Array(text)
        let queryChars = Array(query)

        var textIndex = 0
        var queryIndex = 0

        while textIndex < textChars.count && queryIndex < queryChars.count {
            if textChars[textIndex] == queryChars[queryIndex] {
                queryIndex += 1
            }
            textIndex += 1
        }

        return queryIndex == queryChars.count
    }

    private func matches(_ content: ClipboardContent, filter: ContentFilter) -> Bool {
        switch (content, filter) {
        case (.text, .text), (.richText, .text), (.code, .text), (.snippet, .text):
            return true
        case (.image, .images):
            return true
        case (.file, .files):
            return true
        case (.link, .links):
            return true
        case (.color, .colors):
            return true
        default:
            return false
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top padding for better visual balance
                Spacer().frame(height: 12)

                // Top controls row
                HStack {
                    // Content type filters
                    contentTypeFilters

                    Spacer()

                    // Compact search
                    compactSearchButton
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

                // Expanded search bar (conditional)
                if isSearchExpanded {
                    expandedSearchBar
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                }

                // Main cards container - centered and full width
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            // Leading spacer for centering
                            if filteredItems.count <= 6 {
                                Spacer().frame(minWidth: 0)
                            }

                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardCardView(
                                    item: item,
                                    index: index + 1,
                                    isSelected: index == selectedIndex
                                )
                                .id(index)
                                .onTapGesture {
                                    selectAndPaste(item, index: index)
                                }
                            }

                            // Trailing spacer for centering
                            if filteredItems.count <= 6 {
                                Spacer().frame(minWidth: 0)
                            }
                        }
                        .padding(.horizontal, 32)
                        .frame(minWidth: geometry.size.width)
                    }
                    .frame(height: 160)
                    .onChange(of: selectedIndex) { newIndex in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }

                // Bottom info bar
                bottomInfoBar
                    .padding(.horizontal, 32)

                // Bottom padding to stick to screen bottom
                Spacer().frame(height: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(overlayBackground)
        .onAppear {
            viewModel.initialize()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.keyboardShortcutNotification)) { _ in
            handleKeyboardInput()
        }
    }

    private var overlayBackground: some View {
        ZStack {
            // Main dark background - full opacity for that solid Paste look
            Color.black.opacity(0.92)

            // Subtle gradient for depth
            LinearGradient(
                colors: [
                    Color.black.opacity(0.1),
                    Color.clear,
                    Color.black.opacity(0.1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Top border highlight
            VStack {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                Spacer()
            }
        }
    }


    private var bottomInfoBar: some View {
        HStack {
            Text("\(filteredItems.count) items")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            if !filteredItems.isEmpty {
                Text("⌥⌘V to toggle • ↑↓ Select • Enter Paste • Esc Close")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 12)
    }

    private var contentTypeFilters: some View {
        HStack(spacing: 6) {
            ForEach(ContentFilter.allCases, id: \.self) { filter in
                filterButton(for: filter)
            }
        }
    }

    private func filterButton(for filter: ContentFilter) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFilter = filter
                selectedIndex = 0 // Reset selection when filter changes
            }
        }) {
            HStack(spacing: 3) {
                Image(systemName: filter.icon)
                    .font(.system(size: 10, weight: .medium))
                if filter == .all || selectedFilter == filter {
                    Text(filter.rawValue)
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .foregroundColor(selectedFilter == filter ? .black : .white.opacity(0.8))
            .padding(.horizontal, selectedFilter == filter ? 8 : 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedFilter == filter ? Color.white.opacity(0.9) : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var compactSearchButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isSearchExpanded.toggle()
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))

                if !searchText.isEmpty {
                    Text("\(searchText.prefix(10))")
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(searchText.isEmpty ? 0.1 : 0.2))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var expandedSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.6))
                .font(.system(size: 14))

            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
                .foregroundColor(.white)

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
            }

            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isSearchExpanded = false
                }
            }) {
                Image(systemName: "chevron.up")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 12))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func selectAndPaste(_ item: ClipboardItem, index: Int) {
        selectedIndex = index
        viewModel.pasteItem(item)
        // Close overlay after pasting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
        }
    }

    private func handleKeyboardInput() {
        // This will be called from the window's keyDown events
        // The actual implementation is in the window class
    }

    // MARK: - Keyboard Navigation Methods

    func navigateLeft() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func navigateRight() {
        if selectedIndex < filteredItems.count - 1 {
            selectedIndex += 1
        }
    }

    func selectByNumber(_ number: Int) {
        let index = number - 1 // Convert 1-based to 0-based
        if index >= 0 && index < filteredItems.count {
            selectedIndex = index
        }
    }

    func pasteCurrentSelection() {
        guard selectedIndex < filteredItems.count else { return }
        let item = filteredItems[selectedIndex]
        selectAndPaste(item, index: selectedIndex)
    }

    func deleteCurrentSelection() {
        guard selectedIndex < filteredItems.count else { return }
        let item = filteredItems[selectedIndex]
        viewModel.deleteItem(item)

        // Adjust selection if needed
        if selectedIndex >= filteredItems.count && selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func closeOverlay() {
        NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
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
}

extension NSApplication {
    static let keyboardShortcutNotification = Notification.Name("keyboardShortcut")
}