import Foundation
import AppKit
import ApplicationServices

// MARK: - Accessibility Manager
/// Handles accessibility permissions and cross-application interaction
/// Essential for global hotkeys, direct pasting, and clipboard management

@MainActor
final class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()

    // MARK: - Permission State
    @Published var hasAccessibilityPermission = false
    @Published var permissionRequestInProgress = false

    // MARK: - Configuration
    private let requiredPermissions: Set<Permission> = [
        .accessibility,
        .inputMonitoring
    ]

    private enum Permission {
        case accessibility
        case inputMonitoring
    }

    private init() {
        checkInitialPermissions()
        setupPermissionMonitoring()
    }

    // MARK: - Permission Checking

    @discardableResult
    func checkAllPermissions() async -> Bool {
        let accessibilityGranted = await checkAccessibilityPermission()
        let inputMonitoringGranted = await checkInputMonitoringPermission()

        hasAccessibilityPermission = accessibilityGranted && inputMonitoringGranted
        return hasAccessibilityPermission
    }

    private func checkInitialPermissions() {
        Task {
            await checkAllPermissions()
        }
    }

    private func checkAccessibilityPermission() async -> Bool {
        return AXIsProcessTrusted()
    }

    private func checkInputMonitoringPermission() async -> Bool {
        // For input monitoring, we check if we can create global event monitors
        let canMonitor = CGPreflightScreenCaptureAccess()
        return canMonitor || AXIsProcessTrusted() // Accessibility often covers input monitoring
    }

    // MARK: - Permission Requests

    func requestPermissions() async {
        guard !permissionRequestInProgress else { return }

        permissionRequestInProgress = true
        defer { permissionRequestInProgress = false }

        await requestAccessibilityPermission()
        await checkAllPermissions()
    }

    nonisolated private func requestAccessibilityPermission() async {
        let trusted = AXIsProcessTrusted()

        if !trusted {
            // Request permission with system prompt
            _ = AXIsProcessTrustedWithOptions([
                "AXTrustedCheckOptionPrompt": true
            ] as CFDictionary)
        }

        if !trusted {
            // Show our custom permission explanation
            await showPermissionExplanation()
        }
    }

    private func showPermissionExplanation() async {
        let alert = NSAlert()
        alert.messageText = "ClipFlow Needs Accessibility Permission"
        alert.informativeText = """
        ClipFlow requires accessibility permission to:

        • Capture global keyboard shortcuts (⌥⌘V)
        • Paste clipboard content directly into other apps
        • Monitor clipboard changes across all applications
        • Provide seamless cross-app clipboard management

        This permission is essential for ClipFlow to function properly. Click "Open System Preferences" to grant access.
        """

        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Continue Without Permission")
        alert.alertStyle = .informational

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            openAccessibilityPreferences()
        }
    }

    private func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Permission Monitoring

    private func setupPermissionMonitoring() {
        // Monitor permission changes every 2 seconds
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                let previousState = self.hasAccessibilityPermission
                await self.checkAllPermissions()

                // Notify if permission state changed
                if previousState != self.hasAccessibilityPermission {
                    self.handlePermissionChange()
                }
            }
        }
    }

    private func handlePermissionChange() {
        if hasAccessibilityPermission {
            print("✅ Accessibility permissions granted")
            NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
        } else {
            print("⚠️ Accessibility permissions revoked")
            NotificationCenter.default.post(name: .accessibilityPermissionRevoked, object: nil)
        }
    }

    // MARK: - Application Interaction

    func canInteractWithApplications() -> Bool {
        return hasAccessibilityPermission
    }

    func getFrontmostApplication() async -> NSRunningApplication? {
        guard hasAccessibilityPermission else { return nil }

        return NSWorkspace.shared.frontmostApplication
    }

    func pasteIntoFrontmostApplication(_ text: String) async -> Bool {
        guard hasAccessibilityPermission else {
            print("❌ Cannot paste: No accessibility permission")
            return false
        }

        // Store current clipboard content
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Set new content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let success = await simulateKeyPress(keyCode: 9, modifiers: [.command]) // V key

        // Restore previous content after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let previousContent = previousContent {
                pasteboard.clearContents()
                pasteboard.setString(previousContent, forType: .string)
            }
        }

        return success
    }

    func simulateKeyPress(keyCode: CGKeyCode, modifiers: [CGEventFlags]) async -> Bool {
        guard hasAccessibilityPermission else { return false }

        let eventSource = CGEventSource(stateID: .hidSystemState)

        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true) else {
            return false
        }

        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        // Set modifiers
        let modifierFlags = modifiers.reduce(CGEventFlags()) { result, modifier in
            result.union(modifier)
        }

        keyDown.flags = modifierFlags
        keyUp.flags = modifierFlags

        // Post events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    // MARK: - Privacy Compliance

    func shouldRequestPermissionOnLaunch() async -> Bool {
        // Only request on first launch or if previously denied
        let hasRequestedBefore = UserDefaults.standard.bool(forKey: "AccessibilityPermissionRequested")
        let wasGranted = UserDefaults.standard.bool(forKey: "AccessibilityPermissionGranted")

        return !hasRequestedBefore || (!wasGranted && !hasAccessibilityPermission)
    }

    func markPermissionRequested() async {
        UserDefaults.standard.set(true, forKey: "AccessibilityPermissionRequested")
        UserDefaults.standard.set(hasAccessibilityPermission, forKey: "AccessibilityPermissionGranted")
    }

    // MARK: - Application Context Detection

    func isPasswordManagerActive() async -> Bool {
        guard let frontApp = await getFrontmostApplication(),
              let bundleId = frontApp.bundleIdentifier else {
            return false
        }

        let passwordManagerBundles = [
            "com.1password.1password7",
            "com.agilebits.onepassword7",
            "com.bitwarden.desktop",
            "com.lastpass.LastPass",
            "com.dashlane.Dashlane",
            "net.shinyfrog.bear",
            "com.apple.keychainaccess"
        ]

        return passwordManagerBundles.contains(bundleId)
    }

    func shouldSuppressClipboardMonitoring() async -> Bool {
        // Suppress monitoring when password managers are active
        return await isPasswordManagerActive()
    }

    // MARK: - Graceful Degradation

    func getAvailableFeatures() -> [String] {
        var features: [String] = []

        if hasAccessibilityPermission {
            features.append("Global hotkeys")
            features.append("Direct pasting")
            features.append("Cross-app clipboard monitoring")
            features.append("Automatic clipboard detection")
        } else {
            features.append("Manual clipboard capture")
            features.append("Clipboard history viewing")
            features.append("Search and organization")
        }

        return features
    }

    func showPermissionRequiredAlert(for feature: String) {
        let alert = NSAlert()
        alert.messageText = "Permission Required"
        alert.informativeText = """
        The feature "\(feature)" requires accessibility permission to function.

        Would you like to grant permission now?
        """
        alert.addButton(withTitle: "Grant Permission")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task {
                await requestPermissions()
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let accessibilityPermissionGranted = Notification.Name("accessibilityPermissionGranted")
    static let accessibilityPermissionRevoked = Notification.Name("accessibilityPermissionRevoked")
}

// MARK: - CGEventFlags Extension

extension CGEventFlags {
    static let command = CGEventFlags.maskCommand
    static let option = CGEventFlags.maskAlternate
    static let shift = CGEventFlags.maskShift
    static let control = CGEventFlags.maskControl
}
