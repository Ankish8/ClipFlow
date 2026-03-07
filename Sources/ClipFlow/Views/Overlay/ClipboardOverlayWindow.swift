import SwiftUI
import AppKit

/// NSHostingView subclass that strips all border/focus-ring drawing.
/// The default NSHostingView can render a 1px border around the window
/// content area, which is visible against Liquid Glass panels.
final class BorderlessHostingView<Content: View>: NSHostingView<Content> {
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Strip any layer border that AppKit may apply
        wantsLayer = true
        layer?.borderWidth = 0
        layer?.borderColor = nil

        // Recursively strip borders from all subviews
        stripBorders(from: self)
    }

    override func layout() {
        super.layout()
        // Re-strip after layout since SwiftUI may recreate subviews
        layer?.borderWidth = 0
        layer?.borderColor = nil
    }

    private func stripBorders(from view: NSView) {
        view.focusRingType = .none
        if let layer = view.layer {
            layer.borderWidth = 0
            layer.borderColor = nil
        }
        for subview in view.subviews {
            stripBorders(from: subview)
        }
    }
}

class ClipboardOverlayWindow: NSPanel {
    private var initialFrame: NSRect = .zero
    private var finalFrame: NSRect = .zero
    private var overlayView: ClipboardOverlayView?
    private var localEventMonitor: Any? // Monitor clicks within our app
    private var globalEventMonitor: Any? // Monitor clicks in other apps
    private var lastInsideClickTime: Date? // Track last inside click to prevent double-firing

    init() {
        // Start with temporary frame - will be set properly in setupWindow
        // .nonactivatingPanel: panel can become key WITHOUT activating ClipFlow
        // or stealing focus from whatever app the user is currently in.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setupWindow()
    }

    private func setupWindow() {
        // Window properties
        isOpaque = false
        backgroundColor = NSColor.clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        autorecalculatesKeyViewLoop = false

        // Prevent any window-level border drawing around the content
        setContentBorderThickness(0, for: .minY)
        setContentBorderThickness(0, for: .maxY)

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
        // Local event monitor - handles clicks within our app
        // This catches clicks on our menu bar, other windows, etc.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isVisible else { return event }

            // Get click location in screen coordinates
            let clickLocation = NSEvent.mouseLocation

            // Check if click is inside window frame
            if self.frame.contains(clickLocation) {
                // Click is inside window - record time and don't close overlay
                self.lastInsideClickTime = Date()
                NSLog("👆 Local: Click inside overlay at \(clickLocation) - keeping open")
                return event
            }

            // Check if click is in any child window (like popovers, menus, etc.)
            if let childWindows = self.childWindows, !childWindows.isEmpty {
                for childWindow in childWindows {
                    if childWindow.isVisible && childWindow.frame.contains(clickLocation) {
                        self.lastInsideClickTime = Date()
                        NSLog("👆 Local: Click in popover/child window at \(clickLocation) - keeping open")
                        return event
                    }
                }
            }

            // Click is outside window and not in child windows - close overlay
            NSLog("👆 Local: Click outside overlay at \(clickLocation) - closing")
            NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
            return event
        }

        // Global event monitor - handles clicks in other apps (desktop, other applications)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isVisible else { return }

            // Check if this global event is happening right after an inside click
            // If so, ignore it (it's just the focus change from clicking inside)
            if let lastClick = self.lastInsideClickTime {
                let timeSinceLastClick = Date().timeIntervalSince(lastClick)
                if timeSinceLastClick < 0.2 {  // 200ms window
                    NSLog("👆 Global: Ignoring - recent inside click (\(Int(timeSinceLastClick * 1000))ms ago)")
                    return
                }
            }

            // Real click in another app - close the overlay
            NSLog("👆 Global: Click in other app - closing overlay")
            NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)
        }
    }

    private func setupFrames() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        // Give the rounded panel a little breathing room inside the borderless
        // window so the outer corners and top edge don't get visually clipped.
        let overlayHeight: CGFloat = 340
        let horizontalMargin: CGFloat = 8  // Gap from left/right screen edges
        let bottomMargin: CGFloat = 8      // Gap above the dock (matches horizontal margin)

        // Final position: floating panel with margins on all sides
        finalFrame = NSRect(
            x: screenFrame.minX + horizontalMargin,
            y: screenFrame.minY + bottomMargin,
            width: screenFrame.width - horizontalMargin * 2,
            height: overlayHeight
        )

        // Initial position: hidden below screen (for slide-up animation)
        initialFrame = NSRect(
            x: screenFrame.minX + horizontalMargin,
            y: screenFrame.minY - overlayHeight,
            width: screenFrame.width - horizontalMargin * 2,
            height: overlayHeight
        )
    }

    func showOverlay() {
        // Refresh frame calculations in case screen changed
        setupFrames()

        // Start from hidden position
        setFrame(initialFrame, display: false)
        alphaValue = 1.0
        makeKeyAndOrderFront(nil)

        // Animate sliding up from bottom with subtle spring animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            // Subtle spring animation - reduced bounce
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 1.1, 0.3, 0.9)
            context.allowsImplicitAnimation = true

            // Slide up to final position
            animator().setFrame(finalFrame, display: true)
        }, completionHandler: {
            // Recalculate shadow after animation settles so it follows the rounded
            // glass corners rather than the rectangular window frame.
            Task { @MainActor in self.invalidateShadow() }
        })
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

    // Cleanup is handled automatically via weak self in the event monitor closures
    deinit {
        // Note: Both local and global event monitors are automatically cleaned up
        // We use weak self in the closures to prevent retain cycles
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Window-level card drag detection

    // Track mouseDown position so we can find the drag source when threshold is exceeded.
    // This runs before hitTest dispatch, so glass-effect z-ordering never blocks drags.
    private var dragTrackStartPoint: NSPoint? = nil

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragTrackStartPoint = event.locationInWindow

        case .leftMouseDragged:
            if let startP = dragTrackStartPoint {
                let curP = event.locationInWindow
                let dist = hypot(curP.x - startP.x, curP.y - startP.y)
                if dist > 4 {
                    dragTrackStartPoint = nil
                    if let cardView = findCardDragView(at: startP) {
                        NSLog("🟢 sendEvent: drag started from startP=\(startP), found=\(type(of: cardView))")
                        cardView.beginDragFromWindow(event: event, startPoint: startP)
                        // Don't return early — super dispatches to the view too,
                        // but CardDragView.mouseDragged guards on dragStarted so it's a no-op.
                    } else {
                        NSLog("🔴 sendEvent: drag threshold exceeded at startP=\(startP) but findCardDragView=nil")
                    }
                }
            }

        case .leftMouseUp:
            dragTrackStartPoint = nil

        default:
            break
        }
        super.sendEvent(event)
    }

    /// DFS search for the DragSourceView whose bounds contain `windowPoint`.
    private func findCardDragView(at windowPoint: NSPoint) -> DragSourceView? {
        func search(_ view: NSView) -> DragSourceView? {
            if let dsv = view as? DragSourceView {
                let fromView: NSView? = nil
                let localP = dsv.convert(windowPoint, from: fromView)
                if dsv.bounds.contains(localP) { return dsv }
            }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        guard let cv = contentView else { return nil }
        return search(cv)
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        // Suppress focus ring on any view that becomes first responder
        if let view = responder as? NSView {
            view.focusRingType = .none
        }
        return super.makeFirstResponder(responder)
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