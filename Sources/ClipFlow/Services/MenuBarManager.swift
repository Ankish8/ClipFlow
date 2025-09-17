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
    private var popover: NSPopover?
    private var eventMonitor: EventMonitor?

    // MARK: - State Management
    @Published var isPopoverVisible = false
    @Published var recentItems: [ClipboardItem] = []
    @Published var collections: [Collection] = []
    @Published var searchText = ""

    // MARK: - Services
    private let clipboardService = ClipboardService.shared
    let overlayManager = OverlayManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Configuration
    private let maxRecentItems = 10
    private let popoverWidth: CGFloat = 380
    private let popoverHeight: CGFloat = 500

    private override init() {
        super.init()
        setupMenuBar()
        setupEventMonitor()
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

            // Set up click handling
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // Accessibility
            button.toolTip = "ClipFlow - Clipboard Manager"
        }

        print("✅ Menu bar status item created successfully")
    }

    private func setupEventMonitor() {
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self = self, self.isPopoverVisible else { return }

            // Close popover when clicking outside or pressing escape
            if event.type == .keyDown && event.keyCode == 53 { // Escape key
                self.hidePopover()
            } else if event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.hidePopover()
            }
        }
    }

    private func setupNotifications() {
        // Listen for clipboard updates
        clipboardService.itemUpdates
            .sink { [weak self] item in
                NSLog("📡 MenuBar received clipboard update: \(item.content.contentType)")
                Task { @MainActor in
                    await self?.updateRecentItems(with: item)
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


    // MARK: - Popover Management

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if isPopoverVisible {
            hidePopover()
        } else {
            showPopover()
        }
    }

    @objc func showPopover() {
        guard let statusButton = statusItem?.button else { return }

        if popover == nil {
            createPopover()
        }

        guard let popover = popover else { return }

        // Update data before showing
        Task {
            await loadRecentItems()
            await loadCollections()
        }

        popover.show(relativeTo: statusButton.bounds, of: statusButton, preferredEdge: .minY)
        isPopoverVisible = true
        eventMonitor?.start()

        // Ensure popover gets focus for keyboard navigation
        popover.contentViewController?.view.window?.makeKey()
    }

    func hidePopover() {
        popover?.performClose(nil)
        isPopoverVisible = false
        eventMonitor?.stop()
    }

    private func createPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: popoverWidth, height: popoverHeight)
        popover?.behavior = .transient
        popover?.delegate = self

        // Create SwiftUI content embedded in AppKit
        let contentView = MenuBarContentView(manager: self)
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame.size = popover?.contentSize ?? .zero

        popover?.contentViewController = hostingController
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // Quick Actions
        menu.addItem(NSMenuItem(title: "Show Overlay", action: #selector(showOverlay), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show History", action: #selector(showPopover), keyEquivalent: ""))
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
        // Add new item to the beginning
        recentItems.insert(newItem, at: 0)

        // Remove duplicates and limit to max count
        recentItems = Array(recentItems.prefix(maxRecentItems))

        NSLog("📋 MenuBar updated with new item: \(newItem.content.contentType), total items: \(recentItems.count)")
    }

    // MARK: - Actions

    @objc private func showOverlay() {
        overlayManager.showOverlay()
    }

    @objc private func pasteItem(_ sender: NSMenuItem) {
        guard sender.tag < recentItems.count else { return }
        let item = recentItems[sender.tag]

        Task {
            await clipboardService.pasteItem(item)
        }
    }

    @objc private func showPreferences() {
        // Open the Settings window defined in main.swift
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    // MARK: - Public Interface

    func pasteSelectedItem(_ item: ClipboardItem) {
        hidePopover()

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
        eventMonitor?.stop()
        hidePopover()
        statusItem = nil
    }
}

// MARK: - NSPopoverDelegate

extension MenuBarManager: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        isPopoverVisible = false
        eventMonitor?.stop()
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        return false // Keep as popover, don't detach to window
    }
}

// MARK: - Event Monitor

private class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
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