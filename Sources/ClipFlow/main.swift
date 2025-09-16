import SwiftUI
import ClipFlowBackend

@main
struct ClipFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Hidden window for menu bar app
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayManager: OverlayManager!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("🚀 ClipFlow app launched successfully!")

        // Set app as accessory (no dock icon, runs in background)
        NSApp.setActivationPolicy(.accessory)

        // Initialize overlay manager
        overlayManager = OverlayManager.shared

        // Initialize clipboard monitoring
        Task {
            do {
                print("🔄 Starting clipboard monitoring...")
                try await ClipboardService.shared.startMonitoring()
                print("✅ Clipboard monitoring started successfully")

                // Test current clipboard content
                if let currentItem = await ClipboardService.shared.getCurrentClipboard() {
                    print("📄 Found current clipboard content: \(currentItem.content.displayText)")
                } else {
                    print("📭 No current clipboard content found")
                }

            } catch {
                print("❌ Failed to start clipboard monitoring: \(error)")
                print("ℹ️  Simple clipboard monitoring will be used as fallback")
            }
        }

        print("⌨️ ClipFlow ready! Press ⌥⌘V to open clipboard overlay")
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        print("👋 ClipFlow shutting down...")
        overlayManager?.cleanup()
        Task {
            await ClipboardService.shared.stopMonitoring()
        }
    }
}