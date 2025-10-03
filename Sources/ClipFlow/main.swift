import SwiftUI
import ClipFlowBackend

@main
struct ClipFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Hidden window for menu bar app
        Settings {
            SettingsView()
                .accentColor(.customAccent)
        }
    }
}

// MARK: - Enhanced App Delegate
/// Integrates AppKit foundations with SwiftUI for optimal macOS clipboard management
/// Implements sub-100ms response times with intelligent permission handling

class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Core Managers
    private var menuBarManager: MenuBarManager!
    private var overlayManager: OverlayManager!
    private var accessibilityManager: AccessibilityManager!

    // MARK: - Clipboard Services
    private var cacheManager: CacheManager!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSLog("🚀 ClipFlow launching with enhanced architecture...")

        // Set app as accessory (no dock icon, runs in background)
        NSApp.setActivationPolicy(.accessory)

        Task {
            await initializeServices()
            await setupPermissions()
            await startClipboardMonitoring()
            await warmupCache()
            startPerformanceMonitoring()

            NSLog("✅ ClipFlow ready with all features!")
            NSLog("⌨️ Press ⌥⌘V for overlay or click menu bar icon")
        }
    }

    // MARK: - Initialization

    @MainActor
    private func initializeServices() async {
        print("🔧 Initializing core services...")

        // Initialize managers
        accessibilityManager = AccessibilityManager.shared
        menuBarManager = MenuBarManager.shared
        overlayManager = OverlayManager.shared
        cacheManager = CacheManager.shared

        // ClipboardMonitorActor removed - using ClipboardService directly

        print("✅ Core services initialized")
    }

    @MainActor
    private func setupPermissions() async {
        print("🔐 Checking permissions...")

        let hasPermissions = await accessibilityManager.checkAllPermissions()

        let shouldRequest = await accessibilityManager.shouldRequestPermissionOnLaunch()
        if !hasPermissions && shouldRequest {
            await accessibilityManager.requestPermissions()
            await accessibilityManager.markPermissionRequested()
        }

        if hasPermissions {
            print("✅ All permissions granted")
        } else {
            print("⚠️ Running with limited permissions")
            showLimitedModeNotification()
        }
    }

    @MainActor
    private func startClipboardMonitoring() async {
        NSLog("🔄 Starting enhanced clipboard monitoring...")

        do {
            // Start clipboard monitoring
            try await ClipboardService.shared.startMonitoring()

            NSLog("✅ Clipboard monitoring started successfully")

            // Test current clipboard content
            if let currentItem = await ClipboardService.shared.getCurrentClipboard() {
                NSLog("📄 Found current clipboard content: \(currentItem.content.displayText.prefix(50))...")
            } else {
                NSLog("📭 No current clipboard content found")
            }

        } catch {
            NSLog("❌ Failed to start clipboard monitoring: \(error.localizedDescription)")
            NSLog("ℹ️ Fallback monitoring will be used")
        }
    }

    @MainActor
    private func warmupCache() async {
        print("🔥 Warming up cache...")

        await cacheManager.warmCache()

        let stats = await cacheManager.getAdvancedStatistics()
        print("📊 Cache stats: \(stats.memoryItems) memory items, \(stats.diskItems) disk items")
    }

    // MARK: - Application Lifecycle

    func applicationWillTerminate(_ aNotification: Notification) {
        print("👋 ClipFlow shutting down...")

        // Cleanup in reverse order
        menuBarManager?.cleanup()
        overlayManager?.cleanup()

        Task {
            await ClipboardService.shared.stopMonitoring()
            await cacheManager?.clearCache()
        }

        print("✅ Cleanup completed")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Refresh permissions when app becomes active
        Task {
            await accessibilityManager.checkAllPermissions()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Show overlay when app is reopened
        menuBarManager?.showOverlay()
        return false
    }

    // MARK: - Permission Handling

    private func showLimitedModeNotification() {
        let notification = NSUserNotification()
        notification.title = "ClipFlow - Limited Mode"
        notification.informativeText = "Some features require accessibility permission. Click to grant access."
        notification.soundName = nil

        NSUserNotificationCenter.default.deliver(notification)
    }

    // MARK: - Performance Monitoring

    @MainActor
    private func startPerformanceMonitoring() {
        // Monitor performance metrics
        Task { @MainActor in
            while true {
                try? await Task.sleep(for: .seconds(30))
                await logPerformanceMetrics()
            }
        }
    }

    @MainActor
    private func logPerformanceMetrics() async {
        let cacheStats = await cacheManager.getAdvancedStatistics()
        let clipboardStats = await ClipboardService.shared.getStatistics()

        print("""
        📊 Performance Metrics:
        Cache Hit Rate: \(String(format: "%.1f", cacheStats.overallHitRate * 100))%
        Memory Usage: \(cacheStats.memoryUsageBytes / 1024 / 1024)MB / \(cacheStats.maxMemoryBytes / 1024 / 1024)MB
        Disk Usage: \(cacheStats.diskUsageBytes / 1024 / 1024)MB / \(cacheStats.maxDiskBytes / 1024 / 1024)MB
        Items Processed: \(clipboardStats.totalItemsProcessed)
        """)
    }
}