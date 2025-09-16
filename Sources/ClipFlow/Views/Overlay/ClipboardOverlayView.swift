import SwiftUI
import ClipFlowCore

struct ClipboardOverlayView: View {
    @StateObject private var viewModel = ClipboardViewModel()
    @State private var selectedIndex: Int = 0
    @State private var searchText = ""

    var filteredItems: [ClipboardItem] {
        viewModel.filteredItems(for: searchText)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top padding for better visual balance
                Spacer().frame(height: 16)

                // Search bar (conditional)
                if !searchText.isEmpty || filteredItems.count > 10 {
                    searchBar
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

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.6))
                .font(.system(size: 14))

            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
                .foregroundColor(.white)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private func selectAndPaste(_ item: ClipboardItem, index: Int) {
        selectedIndex = index
        viewModel.pasteItem(item)
        // Close overlay after pasting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
        }
    }

    private func handleKeyboardInput() {
        // Handle arrow keys, number keys, enter, etc.
        // This will be implemented to handle keyboard navigation
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
}

extension NSApplication {
    static let keyboardShortcutNotification = Notification.Name("keyboardShortcut")
}