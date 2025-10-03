import SwiftUI
import ClipFlowCore
import ClipFlowBackend

struct SettingsView: View {
    @AppStorage("maxHistoryItems") private var maxHistoryItems = 100
    @AppStorage("pollingInterval") private var pollingInterval = 0.15
    @AppStorage("enableSounds") private var enableSounds = false
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("enableGlobalHotkey") private var enableGlobalHotkey = true
    @AppStorage("autoDeleteAfterDays") private var autoDeleteAfterDays = 30

    var body: some View {
        TabView {
            GeneralSettingsView(
                maxHistoryItems: $maxHistoryItems,
                pollingInterval: $pollingInterval,
                enableSounds: $enableSounds,
                launchAtLogin: $launchAtLogin,
                showInMenuBar: $showInMenuBar
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            AdvancedSettingsView(
                enableGlobalHotkey: $enableGlobalHotkey,
                autoDeleteAfterDays: $autoDeleteAfterDays
            )
            .tabItem {
                Label("Advanced", systemImage: "slider.horizontal.3")
            }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Binding var maxHistoryItems: Int
    @Binding var pollingInterval: Double
    @Binding var enableSounds: Bool
    @Binding var launchAtLogin: Bool
    @Binding var showInMenuBar: Bool

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Max History Items:")
                        Spacer()
                        Stepper(value: $maxHistoryItems, in: 10...1000, step: 10) {
                            Text("\(maxHistoryItems)")
                                .frame(width: 50, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Monitoring Frequency:")
                        Spacer()
                        VStack(alignment: .trailing) {
                            Slider(value: $pollingInterval, in: 0.05...1.0, step: 0.05) {
                                Text("Polling Interval")
                            } minimumValueLabel: {
                                Text("Fast")
                                    .font(.caption)
                            } maximumValueLabel: {
                                Text("Slow")
                                    .font(.caption)
                            }
                            .frame(width: 200)

                            Text("\(String(format: "%.2f", pollingInterval))s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Performance")
            }

            Section {
                Toggle("Enable sound effects", isOn: $enableSounds)
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show in menu bar", isOn: $showInMenuBar)
            } header: {
                Text("Interface")
            }
        }
        .padding()
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @Binding var enableGlobalHotkey: Bool
    @Binding var autoDeleteAfterDays: Int

    var body: some View {
        Form {
            Section {
                Toggle("Enable global hotkey (⌥⌘V)", isOn: $enableGlobalHotkey)

                HStack {
                    Text("Auto-delete items after:")
                    Spacer()
                    Stepper(value: $autoDeleteAfterDays, in: 1...365, step: 1) {
                        Text("\(autoDeleteAfterDays) days")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Clipboard Management")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Data Location")
                        .font(.headline)

                    Text("~/Library/Application Support/ClipFlow/")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundColor(.secondary)

                    HStack {
                        Button("Reveal in Finder") {
                            revealDataFolder()
                        }

                        Spacer()

                        Button("Clear All Data", role: .destructive) {
                            clearAllData()
                        }
                    }
                }
            } header: {
                Text("Storage")
            }
        }
        .padding()
    }

    private func revealDataFolder() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let clipFlowFolder = appSupport.appendingPathComponent("ClipFlow")

        // Create folder if it doesn't exist
        try? FileManager.default.createDirectory(at: clipFlowFolder, withIntermediateDirectories: true)

        NSWorkspace.shared.activateFileViewerSelecting([clipFlowFolder])
    }

    private func clearAllData() {
        Task {
            do {
                try await ClipboardService.shared.clearHistory(olderThan: nil)
            } catch {
                print("Failed to clear data: \(error)")
            }
        }
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 64))
                .foregroundColor(.customAccent)

            VStack(spacing: 4) {
                Text("ClipFlow")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Advanced Clipboard Manager")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                Text("Features:")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    FeatureRow(icon: "doc.text", text: "Smart content detection (text, links, colors, images)")
                    FeatureRow(icon: "square.and.arrow.up", text: "Drag and drop support")
                    FeatureRow(icon: "magnifyingglass", text: "Powerful search and filtering")
                    FeatureRow(icon: "keyboard", text: "Global hotkey support (⌥⌘V)")
                    FeatureRow(icon: "shield", text: "Privacy-focused design")
                }
            }

            Spacer()

            HStack(spacing: 16) {
                Button("GitHub") {
                    openURL("https://github.com/clipflow/clipflow")
                }

                Button("Privacy Policy") {
                    openURL("https://clipflow.app/privacy")
                }

                Button("Support") {
                    openURL("https://clipflow.app/support")
                }
            }
            .buttonStyle(.link)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.customAccent)
                .frame(width: 16)
            Text(text)
                .font(.body)
            Spacer()
        }
    }
}

#Preview {
    SettingsView()
}