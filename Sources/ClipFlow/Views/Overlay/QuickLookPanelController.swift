import SwiftUI
import AppKit
import ClipFlowCore

/// Manages a separate floating NSPanel for Quick Look previews.
/// The panel is centered on screen, above the overlay, and non-activating
/// so the overlay retains key window status for keyboard navigation.
@MainActor
final class QuickLookPanelController {
    static let shared = QuickLookPanelController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var isVisible = false

    private init() {
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .showQuickLookPanel,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let item = notification.userInfo?["item"] as? ClipboardItem else { return }
            Task { @MainActor in
                self?.show(item: item)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .hideQuickLookPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .hideClipboardOverlay,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    func show(item: ClipboardItem) {
        let content = QuickLookPreviewView(
            item: item,
            onEdit: {
                NotificationCenter.default.post(name: .hideQuickLookPanel, object: nil)
                NotificationCenter.default.post(
                    name: .editClipboardItem,
                    object: nil,
                    userInfo: ["itemId": item.id]
                )
            },
            onDismiss: {
                NotificationCenter.default.post(name: .hideQuickLookPanel, object: nil)
            }
        )

        if let panel = panel {
            // Update content in existing panel
            hostingView?.rootView = AnyView(content)
            if !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFront(nil)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    panel.animator().alphaValue = 1.0
                }
            }
            isVisible = true
            return
        }

        // Create new panel
        let panelWidth: CGFloat = 620
        let panelHeight: CGFloat = 460

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        // Float above the overlay panel (.floating + 1)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.animationBehavior = .utilityWindow

        let hosting = NSHostingView(rootView: AnyView(content))
        p.contentView = hosting
        hostingView = hosting

        // Center above the overlay (vertically centered on screen)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.midY - panelHeight / 2 + 60 // Slightly above center since overlay is at bottom
            p.setFrameOrigin(NSPoint(x: x, y: y))
            NSLog("🔍 QuickLook panel positioned at (\(x), \(y)) — screen: \(screenFrame)")
        }

        panel = p

        // Animate in
        p.alphaValue = 0
        p.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1.0
        }

        isVisible = true
    }

    func hide() {
        guard let panel = panel, isVisible else { return }
        isVisible = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        })
    }

    func toggle(item: ClipboardItem) {
        if isVisible {
            hide()
        } else {
            show(item: item)
        }
    }

    var isShowing: Bool { isVisible }
}
