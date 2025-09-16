import SwiftUI
import AppKit
import KeyboardShortcuts

@MainActor
class OverlayManager: ObservableObject {
    static let shared = OverlayManager()

    private var overlayWindow: ClipboardOverlayWindow?
    @Published var isVisible = false

    private init() {
        setupNotifications()
        setupKeyboardShortcuts()
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
        KeyboardShortcuts.onKeyUp(for: .toggleClipFlowOverlay) {
            Task { @MainActor in
                self.toggleOverlay()
            }
        }
    }

    func showOverlay() {
        if overlayWindow == nil {
            createOverlayWindow()
        }

        guard let window = overlayWindow else { return }

        window.showOverlay()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        isVisible = true
    }

    func hideOverlay() {
        overlayWindow?.hideOverlay()
        isVisible = false
    }

    func toggleOverlay() {
        if isVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    private func createOverlayWindow() {
        overlayWindow = ClipboardOverlayWindow()

        // Set up the SwiftUI content
        let contentView = ClipboardOverlayView()
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

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