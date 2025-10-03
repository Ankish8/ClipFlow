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
    @State private var selectedTab: ContentViewTab = .clipboard
    
    enum ContentViewTab: String, CaseIterable {
        case clipboard = "Clipboard"
        case tags = "Tags"
        case settings = "Settings"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(ContentViewTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 16, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                            
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Content based on selected tab
            Group {
                switch selectedTab {
                case .clipboard:
                    clipboardContent
                case .tags:
                    TagManagementView()
                case .settings:
                    SettingsView()
                }
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
    
    private var clipboardContent: some View {
        HSplitView {
            // Sidebar with search and list
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                
                // Tag filter chips
                if !viewModel.selectedTagIds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(viewModel.selectedTagIds), id: \.self) { tagId in
                                if let tag = viewModel.availableTags.first(where: { $0.id == tagId }) {
                                    TagChipView(
                                        tag: tag,
                                        isSelected: true
                                    ) {
                                        viewModel.toggleTagSelection(tagId)
                                    }
                                }
                            }
                            
                            Button("Clear") {
                                viewModel.clearTagSelection()
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                }

                ClipboardItemsList(
                    items: viewModel.selectedTagIds.isEmpty ? 
                        viewModel.filteredItems(for: searchText) : 
                        viewModel.itemsFilteredByTags(),
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

// MARK: - Tab Extensions

extension ContentView.ContentViewTab {
    var systemImage: String {
        switch self {
        case .clipboard: return "list.bullet.rectangle"
        case .tags: return "tag.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

