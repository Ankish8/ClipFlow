import SwiftUI
import AppKit

class ClipboardOverlayWindow: NSWindow {
    private var initialFrame: NSRect = .zero
    private var finalFrame: NSRect = .zero

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
    }

    private func setupFrames() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let overlayHeight: CGFloat = 220 // Taller to accommodate cards better

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

        // Animate sliding up from bottom
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true

            // Slide up to final position
            animator().setFrame(finalFrame, display: true)
        }
    }

    func hideOverlay() {
        // Animate sliding down and fade out
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            hideOverlay()
        } else {
            super.keyDown(with: event)
        }
    }
}