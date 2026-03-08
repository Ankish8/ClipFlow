import SwiftUI
import AppKit
import ClipFlowCore

/// Horizontal chip bar for app filtering
struct AppChipBarView: View {
    let items: [ClipboardItem]
    @Binding var selectedApps: Set<String>
    @Environment(\.colorScheme) var colorScheme

    // PERFORMANCE: Cache appList and icon images to avoid O(n) dict+sort and NSImage(data:) per render
    @State private var cachedAppList: [AppChip] = []
    @State private var iconCache: [String: Image] = [:]

    private var displayedApps: [AppChip] {
        Array(cachedAppList.prefix(5))
    }

    private var hasMoreApps: Bool {
        cachedAppList.count > 5
    }

    private func rebuildAppList() {
        var appMap: [String: AppChip] = [:]

        for item in items {
            guard let bundleID = item.source.applicationBundleID else { continue }

            if let existing = appMap[bundleID] {
                appMap[bundleID] = AppChip(
                    bundleID: bundleID,
                    name: existing.name,
                    icon: existing.icon,
                    count: existing.count + 1
                )
            } else {
                appMap[bundleID] = AppChip(
                    bundleID: bundleID,
                    name: item.source.applicationName ?? "Unknown",
                    icon: item.source.applicationIcon,
                    count: 1
                )
            }
        }

        cachedAppList = appMap.values.sorted { $0.count > $1.count }

        // Decode icons off main path for any new bundle IDs
        for app in cachedAppList where iconCache[app.bundleID] == nil {
            if let iconData = app.icon {
                let bid = app.bundleID
                Task.detached(priority: .utility) {
                    if let nsImage = NSImage(data: iconData) {
                        let img = Image(nsImage: nsImage)
                        await MainActor.run { iconCache[bid] = img }
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip to clear filters
                allChip

                // App chips
                ForEach(displayedApps, id: \.bundleID) { app in
                    appChip(for: app)
                }

                // "+N more" chip if needed
                if hasMoreApps {
                    moreChip
                }
            }
            .padding(.horizontal, 32)
        }
        .frame(height: 32)
        .onAppear { rebuildAppList() }
        .onChange(of: items) { _, _ in rebuildAppList() }
    }

    private var allChip: some View {
        let isSelected = selectedApps.isEmpty

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedApps.removeAll()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12, weight: .medium))

                Text("All")
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glass(isSelected ? .regular.tint(Color.accentColor.opacity(0.5)).interactive() : .regular.interactive()))
    }

    private func appChip(for app: AppChip) -> some View {
        let isSelected = selectedApps.contains(app.bundleID)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedApps = [app.bundleID]
            }
        }) {
            HStack(spacing: 6) {
                // App icon (cached)
                if let cachedIcon = iconCache[app.bundleID] {
                    cachedIcon
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 16, height: 16)
                }

                // App name
                Text(app.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)

                // Count badge
                Text("\(app.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glass(isSelected ? .regular.tint(Color.accentColor.opacity(0.5)).interactive() : .regular.interactive()))
    }

    private var moreChip: some View {
        Button(action: {
            // TODO: Show full app list
        }) {
            HStack(spacing: 4) {
                Text("+\(cachedAppList.count - 5)")
                    .font(.system(size: 12, weight: .medium))

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
    }
}

// App chip data structure
struct AppChip {
    let bundleID: String
    let name: String
    let icon: Data?
    let count: Int
}
