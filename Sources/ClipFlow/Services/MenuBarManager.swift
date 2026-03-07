import AppKit
import SwiftUI
import Combine
import KeyboardShortcuts
import ClipFlowBackend
import ClipFlowCore

// MARK: - Menu Bar Manager
/// AppKit-based menu bar foundation with embedded SwiftUI views for optimal flexibility
/// Provides superior control over menu behavior and broader macOS compatibility (10.15+)

@MainActor
final class MenuBarManager: NSObject, ObservableObject {
    static let shared = MenuBarManager()

    // MARK: - AppKit Components
    private var statusItem: NSStatusItem?

    // MARK: - State Management
    @Published var recentItems: [ClipboardItem] = []
    @Published var collections: [Collection] = []

    // MARK: - Services
    private let clipboardService = ClipboardService.shared
    let overlayManager = OverlayManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Configuration
    private let maxRecentItems = 10

    private override init() {
        super.init()
        setupMenuBar()
        setupNotifications()
        loadInitialData()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        // Create status item with variable length
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem = statusItem else {
            print("❌ Failed to create status item")
            return
        }

        // Configure status button
        if let button = statusItem.button {
            // Use SF Symbol for modern appearance
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipFlow")
            image?.isTemplate = true // Adapts to light/dark mode
            button.image = image

            // Set up click handling - only context menu on right click
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // Accessibility
            button.toolTip = "ClipFlow - Clipboard Manager (⌥⌘V to open)"
        }

        print("✅ Menu bar status item created successfully")
    }

    private func setupNotifications() {
        // Listen for clipboard updates
        clipboardService.itemUpdates
            .sink { [weak self] item in
                NSLog("📡 MenuBar received clipboard update: \(item.content.contentType)")
                Task { @MainActor in
                    await self?.updateRecentItems(with: item)

                    // Play feedback sound if enabled
                    if UserDefaults.standard.bool(forKey: "enableSounds") {
                        NSSound(named: "Tink")?.play()
                    }
                }
            }
            .store(in: &cancellables)

        NSLog("📡 MenuBar subscribed to clipboard updates")

        // Listen for collection updates
        NotificationCenter.default.addObserver(
            forName: .collectionsUpdated,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await self.loadCollections()
            }
        }
    }

    private func loadInitialData() {
        Task {
            await loadRecentItems()
            await loadCollections()
        }
    }


    // MARK: - Menu Bar Click Handling

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // Always show context menu on any click
        showContextMenu()
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // Quick Actions
        menu.addItem(NSMenuItem(title: "Show Overlay (⌥⌘V)", action: #selector(showOverlay), keyEquivalent: ""))

        // Pause / Resume toggle
        let isPaused = clipboardService.isPaused
        let pauseItem = NSMenuItem(
            title: isPaused ? "Resume Recording" : "Pause Recording",
            action: #selector(togglePauseRecording),
            keyEquivalent: ""
        )
        menu.addItem(pauseItem)

        menu.addItem(NSMenuItem.separator())

        // Recent items submenu
        let recentMenu = NSMenu()
        for (index, item) in recentItems.prefix(5).enumerated() {
            let title = item.content.displayText.truncated(to: 50)
            let menuItem = NSMenuItem(title: "\(index + 1). \(title)", action: #selector(pasteItem(_:)), keyEquivalent: "")
            menuItem.tag = index
            recentMenu.addItem(menuItem)
        }

        if !recentItems.isEmpty {
            let recentMenuItem = NSMenuItem(title: "Recent Items", action: nil, keyEquivalent: "")
            recentMenuItem.submenu = recentMenu
            menu.addItem(recentMenuItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Settings and controls
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About ClipFlow", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ClipFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Set targets
        for item in menu.items {
            item.target = self
        }

        // Show menu
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Remove menu after showing
    }

    // MARK: - Data Management

    private func loadRecentItems() async {
        do {
            let items = try await clipboardService.getRecentItems(limit: maxRecentItems)
            recentItems = items
            NSLog("📋 MenuBar loaded \(items.count) recent items")
        } catch {
            NSLog("❌ Failed to load recent items: \(error.localizedDescription)")
        }
    }

    private func loadCollections() async {
        do {
            collections = try await clipboardService.getCollections()
        } catch {
            print("Failed to load collections: \(error)")
        }
    }

    private func updateRecentItems(with newItem: ClipboardItem) async {
        // Remove any existing duplicates first (by ID or hash)
        recentItems.removeAll { existingItem in
            existingItem.id == newItem.id || existingItem.metadata.hash == newItem.metadata.hash
        }

        // Add new item to the beginning
        recentItems.insert(newItem, at: 0)

        // Limit to max count
        recentItems = Array(recentItems.prefix(maxRecentItems))

        NSLog("📋 MenuBar updated with new item: \(newItem.content.contentType), total items: \(recentItems.count)")
    }

    // MARK: - Actions

    @objc func showOverlay() {
        overlayManager.showOverlay()
    }

    @objc private func togglePauseRecording() {
        if clipboardService.isPaused {
            clipboardService.resumeMonitoring()
            updateStatusIcon(paused: false)
        } else {
            clipboardService.pauseMonitoring()
            updateStatusIcon(paused: true)
        }
    }

    private func updateStatusIcon(paused: Bool) {
        guard let button = statusItem?.button else { return }
        let symbolName = paused ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ClipFlow")
        image?.isTemplate = true
        button.image = image
        button.toolTip = paused
            ? "ClipFlow - Recording Paused"
            : "ClipFlow - Clipboard Manager (⌥⌘V to open)"
    }

    @objc private func pasteItem(_ sender: NSMenuItem) {
        guard sender.tag < recentItems.count else { return }
        let item = recentItems[sender.tag]

        Task {
            await clipboardService.pasteItem(item)
        }
    }

    @objc private func showPreferences() {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    // MARK: - Public Interface

    func pasteSelectedItem(_ item: ClipboardItem) {
        Task {
            await clipboardService.pasteItem(item)
        }
    }

    func deleteItem(_ item: ClipboardItem) {
        Task {
            try await clipboardService.deleteItem(item.id)
            await loadRecentItems()
        }
    }

    func addToCollection(_ item: ClipboardItem, collection: Collection) {
        Task {
            try await clipboardService.addItemToCollection(item.id, collectionId: collection.id)
            await loadCollections()
        }
    }

    func searchItems(query: String) async -> [ClipboardItem] {
        do {
            return try await clipboardService.searchItems(query: query, limit: 20)
        } catch {
            print("Search failed: \(error)")
            return []
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        statusItem = nil
    }
}

// MARK: - Supporting Types

extension Notification.Name {
    static let collectionsUpdated = Notification.Name("collectionsUpdated")
}

private extension String {
    func truncated(to length: Int) -> String {
        if count <= length {
            return self
        } else {
            return String(prefix(length - 3)) + "..."
        }
    }
}