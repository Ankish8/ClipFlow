import SwiftUI
import ClipFlowCore

/// Horizontal chip bar for app filtering
struct AppChipBarView: View {
    let items: [ClipboardItem]
    @Binding var selectedApps: Set<String>
    @Environment(\.colorScheme) var colorScheme

    // Collect unique apps from clipboard items
    private var appList: [AppChip] {
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

        return appMap.values.sorted { $0.count > $1.count }
    }

    private var displayedApps: [AppChip] {
        Array(appList.prefix(5)) // Show top 5 apps
    }

    private var hasMoreApps: Bool {
        appList.count > 5
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
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ?
                        Color.accentColor :
                        Color.primary.opacity(colorScheme == .light ? 0.06 : 0.12)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSelected ?
                                Color.accentColor.opacity(0.3) :
                                Color.primary.opacity(0.15),
                                lineWidth: isSelected ? 0 : 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func appChip(for app: AppChip) -> some View {
        let isSelected = selectedApps.contains(app.bundleID)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                // Single-select: clear all and select only this app
                selectedApps = [app.bundleID]
            }
        }) {
            HStack(spacing: 6) {
                // App icon
                if let iconData = app.icon,
                   let nsImage = NSImage(data: iconData) {
                    Image(nsImage: nsImage)
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
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ?
                                Color.white.opacity(0.2) :
                                Color.secondary.opacity(0.12))
                    )
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ?
                        Color.accentColor :
                        Color.primary.opacity(colorScheme == .light ? 0.06 : 0.12)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSelected ?
                                Color.accentColor.opacity(0.3) :
                                Color.primary.opacity(0.15),
                                lineWidth: isSelected ? 0 : 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var moreChip: some View {
        Button(action: {
            // TODO: Show full app list
        }) {
            HStack(spacing: 4) {
                Text("+\(appList.count - 5)")
                    .font(.system(size: 12, weight: .medium))

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .light ? 0.06 : 0.12))
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// App chip data structure
struct AppChip {
    let bundleID: String
    let name: String
    let icon: Data?
    let count: Int
}
