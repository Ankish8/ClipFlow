import SwiftUI
import AppKit

class ClipboardOverlayWindow: NSWindow {
    private var initialFrame: NSRect = .zero
    private var finalFrame: NSRect = .zero
    private var overlayView: ClipboardOverlayView?

    init() {
        // Start with temporary frame - will be set properly in setupWindow
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        setupWindow()
    }

    private func setupWindow() {
        // Window properties
        isOpaque = false
        backgroundColor = NSColor.clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false

        // Setup frames for animation
        setupFrames()

        // Start positioned off-screen (below bottom)
        setFrame(initialFrame, display: false)

        // Make window initially hidden
        alphaValue = 0.0
        orderOut(nil)

        // Monitor clicks outside the overlay
        setupOutsideClickMonitoring()
    }

    private func setupOutsideClickMonitoring() {
        // Global event monitor for clicks outside the overlay
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isVisible else { return }

            // If overlay is visible and user clicks anywhere globally, dismiss it
            self.hideOverlay()
        }
    }

    private func setupFrames() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let overlayHeight: CGFloat = 300 // Compact height - internal spacing optimized

        // Final position: full width, stuck to bottom
        finalFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width,
            height: overlayHeight
        )

        // Initial position: same width, positioned below screen (for slide-up animation)
        initialFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY - overlayHeight, // Completely hidden below screen
            width: screenFrame.width,
            height: overlayHeight
        )
    }

    func showOverlay() {
        // Refresh frame calculations in case screen changed
        setupFrames()

        // Start from hidden position
        setFrame(initialFrame, display: false)
        alphaValue = 1.0
        orderFront(nil)

        // Animate sliding up from bottom with subtle spring animation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            // Subtle spring animation - reduced bounce
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 1.1, 0.3, 0.9)
            context.allowsImplicitAnimation = true

            // Slide up to final position
            animator().setFrame(finalFrame, display: true)
        }
    }

    func hideOverlay() {
        // Animate sliding down with spring animation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            // Smooth spring animation for hide (less bouncy than show)
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            context.allowsImplicitAnimation = true

            // Slide down to hidden position
            animator().setFrame(initialFrame, display: true)
            animator().alphaValue = 0.8
        } completionHandler: {
            Task { @MainActor in
                self.orderOut(nil)
            }
        }
    }

    func setOverlayView(_ view: ClipboardOverlayView) {
        overlayView = view
    }

    // Remove the global event monitor when window is deallocated
    deinit {
        // Note: In production, we should store the monitor reference and remove it
        // For now, we'll rely on weak self to prevent retain cycles
    }

    override func keyDown(with event: NSEvent) {
        guard let overlayView = overlayView else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 53: // Escape
            overlayView.closeOverlay()

        case 36: // Enter/Return
            overlayView.pasteCurrentSelection()

        case 51, 117: // Delete/Backspace
            overlayView.deleteCurrentSelection()

        case 123: // Left arrow
            overlayView.navigateLeft()

        case 124: // Right arrow
            overlayView.navigateRight()

        case 18...26: // Number keys 1-9
            let number = Int(event.keyCode) - 17 // Convert keycode to number (1-9)
            if number >= 1 && number <= 9 {
                overlayView.selectByNumber(number)
            }

        default:
            super.keyDown(with: event)
        }
    }
}