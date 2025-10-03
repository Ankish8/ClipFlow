import SwiftUI
import ClipFlowCore

/// Represents a unique source application for filtering
struct AppFilterItem: Identifiable, Hashable {
    let id: String // Bundle ID
    let name: String
    let icon: NSImage?
    let itemCount: Int

    init(bundleID: String, name: String, icon: Data?, itemCount: Int) {
        self.id = bundleID
        self.name = name
        self.icon = icon != nil ? NSImage(data: icon!) : nil
        self.itemCount = itemCount
    }
}

/// App filter view component showing source applications
struct AppFilterView: View {
    let items: [ClipboardItem]
    @Binding var selectedApps: Set<String>
    @Environment(\.colorScheme) var colorScheme

    private var appFilters: [AppFilterItem] {
        // Group items by app bundle ID and count them
        var appCounts: [String: (name: String, icon: Data?, count: Int)] = [:]

        for item in items {
            guard let bundleID = item.source.applicationBundleID else { continue }

            if let existing = appCounts[bundleID] {
                appCounts[bundleID] = (
                    name: existing.name,
                    icon: existing.icon,
                    count: existing.count + 1
                )
            } else {
                appCounts[bundleID] = (
                    name: item.source.applicationName ?? "Unknown",
                    icon: item.source.applicationIcon,
                    count: 1
                )
            }
        }

        // Convert to AppFilterItem array and sort by count
        return appCounts.map { bundleID, info in
            AppFilterItem(
                bundleID: bundleID,
                name: info.name,
                icon: info.icon,
                itemCount: info.count
            )
        }.sorted { $0.itemCount > $1.itemCount }
    }

    private var displayedApps: [AppFilterItem] {
        // Show top 6 apps, or fewer if there aren't that many
        Array(appFilters.prefix(6))
    }

    private var hasMoreApps: Bool {
        appFilters.count > 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text("APPS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.top, 8)

            // App filter buttons
            VStack(spacing: 6) {
                ForEach(displayedApps) { app in
                    appFilterButton(for: app)
                }

                // Show more button if needed
                if hasMoreApps {
                    showMoreButton
                }
            }
        }
    }

    private func appFilterButton(for app: AppFilterItem) -> some View {
        let isSelected = selectedApps.contains(app.id)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedApps.remove(app.id)
                } else {
                    selectedApps.insert(app.id)
                }
            }
        }) {
            HStack(spacing: 6) {
                // App icon
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }

                // App name (truncated if too long)
                Text(app.name)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .primary : .secondary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                // Item count badge
                Text("\(app.itemCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ?
                                Color.accentColor.opacity(0.12) :
                                Color.secondary.opacity(0.08))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 72)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ?
                        Color.accentColor.opacity(0.10) :
                        Color.primary.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ?
                                Color.accentColor.opacity(0.3) :
                                Color.primary.opacity(0.06),
                                lineWidth: isSelected ? 1.5 : 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(app.name)
    }

    private var showMoreButton: some View {
        Button(action: {
            // TODO: Implement full app list view
        }) {
            HStack(spacing: 4) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))

                Text("More")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(.secondary.opacity(0.8))
            .frame(width: 72, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
