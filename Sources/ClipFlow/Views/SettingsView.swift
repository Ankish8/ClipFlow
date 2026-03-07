import SwiftUI
import ServiceManagement
import KeyboardShortcuts
import ClipFlowCore
import ClipFlowBackend

// MARK: - Settings View (Sidebar + Detail)

struct SettingsView: View {
    @State private var selectedPage: SettingsPage = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Label("General", systemImage: "gearshape")
                    .tag(SettingsPage.general)
                Label("Clipboard", systemImage: "doc.on.clipboard")
                    .tag(SettingsPage.clipboard)
                Label("Storage", systemImage: "internaldrive")
                    .tag(SettingsPage.storage)
                Label("Rules", systemImage: "tag.square")
                    .tag(SettingsPage.rules)
                Label("About", systemImage: "info.circle")
                    .tag(SettingsPage.about)
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            Group {
                switch selectedPage {
                case .general:  GeneralSettingsPage()
                case .clipboard: ClipboardSettingsPage()
                case .storage:  StorageSettingsPage()
                case .rules:    RulesSettingsPage()
                case .about:    AboutSettingsPage()
                }
            }
            .id(selectedPage)
        }
    }
}

private enum SettingsPage: Hashable {
    case general, clipboard, storage, rules, about
}

// MARK: - General

private struct GeneralSettingsPage: View {
    @AppStorage("enableSounds") private var enableSounds = false
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }

            Section("Feedback") {
                Toggle("Enable sound effects", isOn: $enableSounds)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onChange(of: launchAtLogin) { _, newValue in
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Revert on failure
                launchAtLogin = !newValue
                NSLog("❌ Failed to \(newValue ? "register" : "unregister") login item: \(error)")
            }
        }
    }
}

// MARK: - Clipboard

private struct ClipboardSettingsPage: View {
    @AppStorage("maxHistoryItems") private var maxHistoryItems = 100
    @AppStorage("pollingInterval") private var pollingInterval = 0.15
    @AppStorage("enableGlobalHotkey") private var enableGlobalHotkey = true
    @AppStorage("autoDeleteAfterDays") private var autoDeleteAfterDays = 30

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Global Hotkey") {
                    HStack(spacing: 12) {
                        KeyboardShortcuts.Recorder(for: .toggleClipFlowOverlay)
                        Toggle("Enabled", isOn: $enableGlobalHotkey)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            Section("Monitoring") {
                LabeledContent("Max history items") {
                    Stepper(value: $maxHistoryItems, in: 10...1000, step: 10) {
                        Text("\(maxHistoryItems)")
                            .monospacedDigit()
                    }
                }

                LabeledContent("Monitoring speed") {
                    HStack(spacing: 6) {
                        Text("Fast").font(.caption2).foregroundStyle(.tertiary)
                        Slider(value: $pollingInterval, in: 0.05...1.0, step: 0.05)
                            .frame(width: 120)
                        Text("Slow").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Section("Cleanup") {
                LabeledContent("Auto-delete after") {
                    Stepper(value: $autoDeleteAfterDays, in: 1...365, step: 1) {
                        Text("\(autoDeleteAfterDays) days")
                            .monospacedDigit()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Clipboard")
        .onChange(of: pollingInterval) { _, newValue in
            Task {
                await ClipboardService.shared.restartMonitoring(interval: newValue)
            }
        }
        .onChange(of: enableGlobalHotkey) { _, newValue in
            if newValue {
                KeyboardShortcuts.enable(.toggleClipFlowOverlay)
            } else {
                KeyboardShortcuts.disable(.toggleClipFlowOverlay)
            }
        }
    }
}

// MARK: - Storage

private struct StorageSettingsPage: View {
    @State private var itemCount: Int?
    @State private var storageStats: StorageStatistics?
    @State private var isLoading = false

    var body: some View {
        Form {
            Section("Data Location") {
                LabeledContent("Path") {
                    Text("~/Library/Application Support/ClipFlow/")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Reveal in Finder") { revealDataFolder() }
                    Spacer()
                    Button("Clear All Data", role: .destructive) { clearAllData() }
                }
            }

            Section("Statistics") {
                if isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading...").foregroundStyle(.secondary)
                    }
                } else if let stats = storageStats {
                    LabeledContent("Total Items", value: "\(itemCount ?? 0)")
                    LabeledContent("Database Size", value: formatBytes(stats.databaseSizeBytes))
                    LabeledContent("Large Content", value: formatBytes(stats.largeContentSizeBytes))
                    LabeledContent("Total Storage", value: formatBytes(stats.totalStorageBytes))
                    LabeledContent("Cache Hit Rate", value: "\(Int(stats.cacheStats.hitRate * 100))%")
                    LabeledContent("Cached Items", value: "\(stats.cacheStats.itemCount)")
                } else {
                    Text("Unable to load statistics")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Storage")
        .task {
            isLoading = true
            do {
                let info = try await ClipboardService.shared.getStorageInfo()
                itemCount = info.count
                storageStats = info.stats
            } catch {}
            isLoading = false
        }
    }

    private func revealDataFolder() {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let folder = dir.appendingPathComponent("ClipFlow")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func clearAllData() {
        Task { try? await ClipboardService.shared.clearHistory(olderThan: nil) }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()

    private func formatBytes(_ bytes: Int64) -> String {
        Self.byteFormatter.string(fromByteCount: bytes)
    }
}

// MARK: - Rules (wraps existing AutoTagRulesView)

private struct RulesSettingsPage: View {
    var body: some View {
        AutoTagRulesView()
            .navigationTitle("Rules")
    }
}

// MARK: - About

private struct AboutSettingsPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(Color.customAccent)

            VStack(spacing: 4) {
                Text("ClipFlow")
                    .font(.title.bold())
                Text("Advanced Clipboard Manager")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(height: 8)

            VStack(alignment: .leading, spacing: 6) {
                featureItem("doc.text", "Smart content detection")
                featureItem("square.and.arrow.up", "Drag and drop support")
                featureItem("magnifyingglass", "Search and filtering")
                featureItem("keyboard", "Global hotkey (⌥⌘V)")
                featureItem("shield", "Privacy-focused design")
                featureItem("eye", "OCR / text recognition")
                featureItem("tag", "Smart auto-tagging rules")
            }

            Spacer()

            HStack(spacing: 16) {
                Button("GitHub") { openURL("https://github.com/clipflow/clipflow") }
                Button("Privacy") { openURL("https://clipflow.app/privacy") }
                Button("Support") { openURL("https://clipflow.app/support") }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }

    private func featureItem(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.customAccent)
                .frame(width: 16)
            Text(text).font(.callout)
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Settings Window Controller
// LSUIElement apps hide all windows when deactivated. To keep the Settings
// window visible we temporarily promote to .regular (shows a dock icon),
// then revert to .accessory when the window closes.

@MainActor
class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func showSettings() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Promote to regular app so the window stays visible on deactivate
        NSApp.setActivationPolicy(.regular)

        let hostingView = NSHostingView(rootView: SettingsView())

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "ClipFlow Settings"
        win.minSize = NSSize(width: 520, height: 360)
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden

        // An NSToolbar with .unified style gives the titlebar proper height
        // so traffic lights sit in their own row above the NavigationSplitView sidebar
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.showsBaselineSeparator = false
        win.toolbar = toolbar
        win.toolbarStyle = .unified
        win.delegate = self

        // Pin hosting view with Auto Layout so SwiftUI drives sizing
        win.contentView = hostingView
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if let container = hostingView.superview {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: container.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        window = win
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Revert to accessory (no dock icon) when Settings closes
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 640, height: 420)
}
