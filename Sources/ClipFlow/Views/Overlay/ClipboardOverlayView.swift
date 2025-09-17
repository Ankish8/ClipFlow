import SwiftUI
import ClipFlowCore

struct ClipboardOverlayView: View {
    @StateObject private var viewModel = ClipboardViewModel()
    @State private var selectedIndex: Int = 0
    @State private var selectedFilter: ContentFilter = .all

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

        // Apply content type filtering
        if selectedFilter != .all {
            items = items.filter { item in
                matches(item.content, filter: selectedFilter)
            }
        }

        return items
    }


    private func matches(_ content: ClipboardContent, filter: ContentFilter) -> Bool {
        switch (content, filter) {
        case (.text(let textContent), .text):
            // Don't show hex colors in text filter since they appear as color cards
            let text = textContent.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !isHexColor(text)
        case (.richText, .text), (.code, .text), (.snippet, .text):
            return true
        case (.text(let textContent), .colors):
            // Show hex colors in colors filter
            let text = textContent.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            return isHexColor(text)
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

    private func isHexColor(_ text: String) -> Bool {
        guard text.hasPrefix("#"), text.count == 7 else { return false }
        let hexValue = String(text.dropFirst())
        return Int(hexValue, radix: 16) != nil
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left sidebar with content type filters
                VStack(spacing: 0) {
                    // Top padding for alignment
                    Spacer().frame(height: 12)

                    // Content type filters (vertical)
                    contentTypeFilters
                        .padding(.horizontal, 10)

                    Spacer()
                }
                .frame(width: 90)

                // Main content area
                VStack(spacing: 0) {
                    // Top padding for better visual balance
                    Spacer().frame(height: 20)

                    // Additional spacing above cards
                    Spacer().frame(height: 16)

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
                                        selectItem(index: index)
                                    }
                                }

                                // Trailing spacer for centering
                                if filteredItems.count <= 6 {
                                    Spacer().frame(minWidth: 0)
                                }
                            }
                            .padding(.horizontal, 32)
                            .frame(minWidth: geometry.size.width - 90)
                        }
                        .frame(height: 220)
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
                    Spacer().frame(height: 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            overlayBackground
                .onTapGesture {
                    // Tap on background dismisses overlay
                    closeOverlay()
                }
                .contentShape(Rectangle())
        )
        .onAppear {
            viewModel.initialize()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.keyboardShortcutNotification)) { _ in
            handleKeyboardInput()
        }
    }

    @Environment(\.colorScheme) var colorScheme

    private var overlayBackground: some View {
        ZStack {
            // Base neutral gradient tuned for contrast with cards
            LinearGradient(
                colors: colorScheme == .light ? [
                    // Slightly darker than before to improve contrast with near-white cards
                    Color(.sRGB, red: 0.86, green: 0.88, blue: 0.90, opacity: 1.0),
                    Color(.sRGB, red: 0.80, green: 0.82, blue: 0.85, opacity: 1.0)
                ] : [
                    // Slightly lighter midtones so dark cards (0.12) stand out over the center
                    Color(.sRGB, red: 0.18, green: 0.18, blue: 0.19, opacity: 1.0),
                    Color(.sRGB, red: 0.12, green: 0.12, blue: 0.13, opacity: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle center spotlight to lift area behind cards
            RadialGradient(
                colors: colorScheme == .light ? [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.0)
                ] : [
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.0)
                ],
                center: .center,
                startRadius: 80,
                endRadius: 600
            )

            // Edge vignette to focus attention and enhance perceived contrast
            LinearGradient(
                colors: colorScheme == .light ? [
                    Color.black.opacity(0.06),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.06)
                ] : [
                    Color.black.opacity(0.12),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.12)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .blendMode(.multiply)
        }
        .ignoresSafeArea()
    }

    private var bottomInfoBar: some View {
        HStack {
            Text("\(filteredItems.count) items")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

        }
        .padding(.vertical, 12)
    }

    private var contentTypeFilters: some View {
        VStack(spacing: 6) {
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
            VStack(spacing: 3) {
                Image(systemName: filter.icon)
                    .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .medium))
                    .foregroundColor(selectedFilter == filter ? .accentColor : .secondary)

                Text(filter.rawValue)
                    .font(.system(size: 9, weight: selectedFilter == filter ? .semibold : .medium))
                    .foregroundColor(selectedFilter == filter ? .primary : .secondary.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(width: 72, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedFilter == filter ?
                        Color.accentColor.opacity(0.12) :
                        Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selectedFilter == filter ?
                                Color.accentColor.opacity(0.2) :
                                Color.primary.opacity(0.08),
                                lineWidth: selectedFilter == filter ? 1.5 : 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }


    private func selectItem(index: Int) {
        selectedIndex = index
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
