import SwiftUI
import AppKit
import KeyboardShortcuts
import ClipFlowBackend

@MainActor
class OverlayManager: ObservableObject {
    static let shared = OverlayManager()

    private var overlayWindow: ClipboardOverlayWindow?
    @Published var isVisible = false

    // Shared ViewModel to persist data between overlay shows/hides
    private let sharedViewModel = ClipboardViewModel()

    // State guards for reliability
    private var isAnimating = false
    private var lastToggleTime: Date?

    // Focus restoration
    private var previousActiveApp: NSRunningApplication?

    private init() {
        setupNotifications()
        setupKeyboardShortcuts()
        // Initialize the shared ViewModel once
        sharedViewModel.initialize()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .showClipboardOverlay,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.showOverlay()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .hideClipboardOverlay,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.hideOverlay()
            }
        }
    }

    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleClipFlowOverlay) { [weak self] in
            // Call directly on main actor - no async Task wrapper for instant response
            self?.toggleOverlay()
        }
    }

    func showOverlay() {
        if overlayWindow == nil {
            createOverlayWindow()
        }

        guard let window = overlayWindow else { return }

        // CRITICAL: Capture the currently active app BEFORE showing overlay
        previousActiveApp = NSWorkspace.shared.frontmostApplication
        if let appName = previousActiveApp?.localizedName {
            NSLog("📍 Captured previous active app: \(appName)")
        }

        isAnimating = true
        NSLog("🎬 Starting show animation")

        window.showOverlay()
        window.orderFront(nil)  // CHANGED: Don't make key - prevents focus steal
        // REMOVED: NSApp.activate - don't steal focus from active text field

        isVisible = true

        // Reset animation flag after animation completes (0.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.isAnimating = false
            NSLog("✅ Show animation complete")
        }
    }

    func hideOverlay() {
        isAnimating = true
        NSLog("🎬 Starting hide animation")

        overlayWindow?.hideOverlay()
        isVisible = false

        // CRITICAL: Restore focus to previous app immediately after hiding
        if let app = previousActiveApp {
            if let appName = app.localizedName {
                NSLog("🔙 Restoring focus to: \(appName)")
            }
            app.activate(options: [])
        }

        // Reset animation flag after animation completes (0.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.isAnimating = false
            NSLog("✅ Hide animation complete")
        }
    }

    func toggleOverlay() {
        // Debouncing: Ignore if < 200ms since last toggle (prevents rapid successive presses)
        let now = Date()
        if let lastTime = lastToggleTime, now.timeIntervalSince(lastTime) < 0.2 {
            NSLog("⏭️ Ignoring rapid toggle (< 200ms since last)")
            return
        }
        lastToggleTime = now

        // Guard against animation in progress
        guard !isAnimating else {
            NSLog("⏸️ Ignoring toggle - animation in progress")
            return
        }

        NSLog("⌨️ Keyboard shortcut fired - toggling overlay (current state: \(isVisible ? "visible" : "hidden"))")

        if isVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    private func createOverlayWindow() {
        overlayWindow = ClipboardOverlayWindow()

        // Set up the SwiftUI content with shared ViewModel
        let contentView = ClipboardOverlayView(viewModel: sharedViewModel)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Connect the view to the window for keyboard handling
        overlayWindow?.setOverlayView(contentView)

        overlayWindow?.contentView = hostingView

        // Set up constraints
        if let contentView = overlayWindow?.contentView {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }

    func cleanup() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        isVisible = false
    }
}

// MARK: - Global Hotkey Support
extension KeyboardShortcuts.Name {
    static let toggleClipFlowOverlay = Self("toggleClipFlowOverlay", default: .init(.v, modifiers: [.command, .option]))
}