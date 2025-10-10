import SwiftUI
import ClipFlowCore
import ClipFlowBackend
import Combine

/// Main tag filter bar view - replaces AppChipBarView
struct TagFilterBarView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    @Binding var selectedTagIds: Set<UUID>
    @Binding var isSearchExpanded: Bool
    @Binding var searchText: String

    @State private var tags: [Tag] = []
    @State private var tagItemCounts: [UUID: Int] = [:]
    @State private var colorPickerStates: [UUID: Bool] = [:]  // Track color picker state for each tag

    // Helper class to hold Combine subscriptions (avoids @State wrapper issues)
    private class SubscriptionHolder {
        var cancellables = Set<AnyCancellable>()
    }
    @State private var subscriptionHolder = SubscriptionHolder()

    // Tag order persistence
    private let tagOrderKey = "tagOrderPreference"

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "Clipboard History" chip to show all items
                clipboardHistoryChip

                // Divider
                divider

                // Tag chips - now with reordering support
                ForEach(tags) { tag in
                    TagChipView(
                        tag: tag,
                        itemCount: tagItemCounts[tag.id] ?? 0,
                        isSelected: selectedTagIds.contains(tag.id),
                        showColorPicker: Binding(
                            get: { colorPickerStates[tag.id] ?? false },
                            set: { colorPickerStates[tag.id] = $0 }
                        ),
                        onTap: {
                            toggleTag(tag.id)
                        },
                        onLongPress: {
                            showTagContextMenu(for: tag)
                        },
                        onDrop: { itemId in
                            handleDrop(itemId: itemId, onTag: tag)
                        },
                        onRename: { newName, completion in
                            performRename(tag: tag, newName: newName, completion: completion)
                        },
                        onColorChange: { newColor in
                            performColorChange(tag: tag, newColor: newColor)
                        }
                    )
                    .contextMenu {
                        tagContextMenu(for: tag)
                    }
                }
                .onMove { fromOffsets, toOffset in
                    moveTag(from: fromOffsets, to: toOffset)
                }

                // Divider before creation tools
                if !tags.isEmpty {
                    divider
                }

                // Inline tag creator
                InlineTagCreator { newTag in
                    handleTagCreated(newTag)
                }

                // Divider
                divider

                // Expandable search bar
                ExpandableSearchBar(
                    searchText: $searchText,
                    isExpanded: $isSearchExpanded,
                    placeholder: "Search clipboard...",
                    onSearch: performSearch
                )
            }
            .padding(.horizontal, 32)
        }
        .frame(height: 32)
        .onAppear {
            loadTags()
            calculateItemCounts()
            setupSubscriptions()
        }
        .onChange(of: viewModel.items) { _ in
            calculateItemCounts()
        }
    }

    // MARK: - Clipboard History Chip

    private var clipboardHistoryChip: some View {
        let isSelected = selectedTagIds.isEmpty

        return Button(action: clearTagFilters) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium))

                Text("Clipboard History")
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ?
                        Color.customAccent :
                        Color.primary.opacity(colorScheme == .light ? 0.06 : 0.12)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSelected ?
                                Color.customAccent.opacity(0.3) :
                                Color.primary.opacity(0.15),
                                lineWidth: isSelected ? 0 : 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .focusEffectDisabled()
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 16)
    }

    // MARK: - Context Menu

    private func tagContextMenu(for tag: Tag) -> some View {
        Group {
            Button("Rename Tag") {
                renameTag(tag)
            }

            Button("Change Color") {
                openColorPickerForTag(tag)
            }

            Divider()

            Button("Delete Tag", role: .destructive) {
                deleteTag(tag)
            }
        }
    }

    // MARK: - Actions

    private func toggleTag(_ tagId: UUID) {
        if selectedTagIds.contains(tagId) {
            selectedTagIds.remove(tagId)
        } else {
            // Single-select: clear all and select only this tag
            selectedTagIds = [tagId]
        }
    }

    private func clearTagFilters() {
        selectedTagIds.removeAll()
    }

    private func handleTagCreated(_ newTag: Tag) {
        // New tags stay at the rightmost position (end of array)
        tags.append(newTag)
        tagItemCounts[newTag.id] = 0
        saveTagOrder()
        NSLog("➕ Created tag '\(newTag.name)' at rightmost position")
    }

    private func performSearch(_ query: String) {
        viewModel.performFullTextSearch(query)
    }

    // MARK: - Tag Management

    private func renameTag(_ tag: Tag) {
        NSLog("📝 Context menu: Starting inline rename for '\(tag.name)'")
        // The TagChipView handles inline rename via double-click or context menu now
        // This function triggers it programmatically if needed
    }

    private func openColorPickerForTag(_ tag: Tag) {
        NSLog("🎨 Context menu: Opening color picker for tag: \(tag.name)")
        colorPickerStates[tag.id] = true
    }

    private func performRename(tag: Tag, newName: String, completion: @escaping (Bool) -> Void) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            NSLog("⚠️ Cannot rename to empty name")
            completion(false)
            return
        }

        guard trimmedName.count <= 30 else {
            NSLog("⚠️ Tag name too long")
            completion(false)
            return
        }

        // Check for duplicates
        if TagService.shared.getAllTags().contains(where: { $0.name.lowercased() == trimmedName.lowercased() && $0.id != tag.id }) {
            NSLog("⚠️ Tag '\(trimmedName)' already exists")
            completion(false)
            return
        }

        Task {
            var updatedTag = tag
            updatedTag.update(name: trimmedName)

            do {
                try await TagService.shared.updateTag(updatedTag)
                NSLog("✅ Renamed '\(tag.name)' to '\(trimmedName)'")
                await MainActor.run {
                    completion(true)
                }
            } catch {
                NSLog("❌ Failed to rename: \(error)")
                await MainActor.run {
                    completion(false)
                }
            }
        }
    }

    private func performColorChange(tag: Tag, newColor: TagColor) {
        NSLog("🎨 Changing '\(tag.name)' to \(newColor.displayName)")

        Task {
            var updatedTag = tag
            updatedTag.update(color: newColor)

            do {
                try await TagService.shared.updateTag(updatedTag)
                NSLog("✅ Color changed")
            } catch {
                NSLog("❌ Failed to change color: \(error)")
            }
        }
    }

    private func deleteTag(_ tag: Tag) {
        Task {
            do {
                try await TagService.shared.deleteTag(id: tag.id)
                tags.removeAll { $0.id == tag.id }
                selectedTagIds.remove(tag.id)
                tagItemCounts.removeValue(forKey: tag.id)
            } catch {
                NSLog("❌ Failed to delete tag: \(error)")
            }
        }
    }

    private func showTagContextMenu(for tag: Tag) {
        // Long press handler - could show different UI
        NSLog("Long press on tag: \(tag.name)")
    }

    private func handleDrop(itemId: UUID, onTag tag: Tag) {
        NSLog("📌 Dropped item \(itemId) on tag: \(tag.name)")

        // Add tag to the dropped item
        viewModel.addTagToItem(tagId: tag.id, itemId: itemId)

        // Update item count for this tag
        calculateItemCounts()

        // Visual feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: - Tag Reordering

    private func moveTag(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)
        saveTagOrder()
        NSLog("🔄 Reordered tags - new order saved")
    }

    private func saveTagOrder() {
        let tagIds = tags.map { $0.id.uuidString }
        UserDefaults.standard.set(tagIds, forKey: tagOrderKey)
        NSLog("💾 Saved tag order: \(tags.map { $0.name }.joined(separator: ", "))")
    }

    private func applySavedTagOrder() {
        guard let savedOrder = UserDefaults.standard.array(forKey: tagOrderKey) as? [String] else {
            NSLog("📋 No saved tag order found - using default")
            return
        }

        let savedUUIDs = savedOrder.compactMap { UUID(uuidString: $0) }
        guard !savedUUIDs.isEmpty else { return }

        // Sort tags according to saved order
        tags.sort { tag1, tag2 in
            let index1 = savedUUIDs.firstIndex(of: tag1.id) ?? Int.max
            let index2 = savedUUIDs.firstIndex(of: tag2.id) ?? Int.max
            return index1 < index2
        }

        NSLog("📥 Restored tag order: \(tags.map { $0.name }.joined(separator: ", "))")
    }

    // MARK: - Data Loading

    private func loadTags() {
        Task {
            await TagService.shared.loadAllTags()
            tags = TagService.shared.getAllTags()
            applySavedTagOrder()
        }
    }

    private func calculateItemCounts() {
        tagItemCounts.removeAll()

        for tag in tags {
            let count = viewModel.items.filter { item in
                item.tagIds.contains(tag.id)
            }.count
            tagItemCounts[tag.id] = count
        }
    }

    private func setupSubscriptions() {
        // Subscribe to tag updates
        TagService.shared.tagUpdates
            .receive(on: DispatchQueue.main)
            .sink { [self] updatedTag in
                if let index = tags.firstIndex(where: { $0.id == updatedTag.id }) {
                    tags[index] = updatedTag
                    NSLog("🔄 UI: Tag '\(updatedTag.name)' updated in view")
                }
            }
            .store(in: &subscriptionHolder.cancellables)

        // Subscribe to tag deletions
        TagService.shared.tagDeleted
            .receive(on: DispatchQueue.main)
            .sink { [self] deletedTagId in
                tags.removeAll { $0.id == deletedTagId }
                selectedTagIds.remove(deletedTagId)
            }
            .store(in: &subscriptionHolder.cancellables)

        // Subscribe to tags loaded
        TagService.shared.tagsLoaded
            .receive(on: DispatchQueue.main)
            .sink { [self] loadedTags in
                tags = loadedTags
                applySavedTagOrder()
                calculateItemCounts()
            }
            .store(in: &subscriptionHolder.cancellables)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var viewModel = ClipboardViewModel()
        @State private var selectedTagIds: Set<UUID> = []
        @State private var isSearchExpanded = false
        @State private var searchText = ""

        var body: some View {
            VStack {
                TagFilterBarView(
                    viewModel: viewModel,
                    selectedTagIds: $selectedTagIds,
                    isSearchExpanded: $isSearchExpanded,
                    searchText: $searchText
                )
                .background(Color.gray.opacity(0.1))

                Spacer()

                Text("Selected tags: \(selectedTagIds.count)")
                    .foregroundColor(.secondary)
            }
            .frame(height: 200)
        }
    }

    return PreviewWrapper()
}
