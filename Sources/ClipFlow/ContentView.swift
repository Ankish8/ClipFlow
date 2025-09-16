import SwiftUI
import Combine
import ClipFlowCore
import ClipFlowAPI
import ClipFlowBackend
import KeyboardShortcuts

struct ContentView: View {
    @StateObject private var viewModel = ClipboardViewModel()
    @State private var searchText = ""
    @State private var selectedItem: ClipboardItem?

    var body: some View {
        HSplitView {
            // Sidebar with search and list
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                ClipboardItemsList(
                    items: viewModel.filteredItems(for: searchText),
                    selectedItem: $selectedItem,
                    viewModel: viewModel
                )
            }
            .frame(minWidth: 300, idealWidth: 400)

            // Detail view
            if let selectedItem = selectedItem {
                DetailView(item: selectedItem, viewModel: viewModel)
                    .frame(minWidth: 400)
            } else {
                EmptyDetailView()
                    .frame(minWidth: 400)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            viewModel.initialize()
            setupKeyboardShortcuts()

            // Simple clipboard test
            Task {
                await testClipboard()
            }
        }
    }

    private func testClipboard() async {
        print("🔍 Testing basic clipboard functionality...")

        // Test basic NSPasteboard access
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        print("📊 Current change count: \(changeCount)")

        if let text = pasteboard.string(forType: .string) {
            print("📝 Current clipboard text: \(text)")
        } else {
            print("📭 No text in clipboard")
        }

        // Test service access
        do {
            let current = await ClipboardService.shared.getCurrentClipboard()
            if let item = current {
                print("✅ Service found clipboard item: \(item.content.displayText)")
            } else {
                print("❌ Service found no clipboard item")
            }
        }
    }

    private func setupKeyboardShortcuts() {
        // This old window-based shortcut is no longer needed since we use overlay
        // KeyboardShortcuts are now handled by OverlayManager
    }
}

