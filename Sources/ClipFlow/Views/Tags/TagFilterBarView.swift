import SwiftUI
import ClipFlowCore
import ClipFlowBackend
import Combine

/// Main tag filter bar view - replaces AppChipBarView
/// Content type filter definition for Power Search chips
struct ContentTypeFilter: Identifiable {
    let id: String       // matches ClipboardContent.contentType
    let label: String
    let icon: String
    let matchTypes: Set<String>  // content types this chip matches (e.g., "text" chip also matches "richText")

    static let filters: [ContentTypeFilter] = [
        ContentTypeFilter(id: "text", label: "Text", icon: "doc.text",
                         matchTypes: ["text", "richText"]),
        ContentTypeFilter(id: "image", label: "Images", icon: "photo",
                         matchTypes: ["image"]),
        ContentTypeFilter(id: "link", label: "Links", icon: "link",
                         matchTypes: ["link"]),
        ContentTypeFilter(id: "code", label: "Code", icon: "chevron.left.forwardslash.chevron.right",
                         matchTypes: ["code", "snippet"]),
        ContentTypeFilter(id: "file", label: "Files", icon: "doc",
                         matchTypes: ["file"]),
        ContentTypeFilter(id: "color", label: "Colors", icon: "paintpalette",
                         matchTypes: ["color"]),
    ]
}

struct TagFilterBarView: View {
    var viewModel: ClipboardViewModel
    @Binding var selectedTagIds: Set<UUID>
    @Binding var selectedContentType: String?
    @Binding var searchText: String

    @State private var tags: [Tag] = []
    @State private var tagItemCounts: [UUID: Int] = [:]
    @State private var colorPickerStates: [UUID: Bool] = [:]  // Track color picker state for each tag
    /// All content types seen in history — cached so tag filtering doesn't hide type chips
    @State private var allItemTypes: Set<String> = []
    /// Pre-computed content type counts — avoids O(n) filter per chip on every render
    @State private var contentTypeCounts: [String: Int] = [:]

    // Helper class to hold Combine subscriptions (avoids @State wrapper issues)
    private class SubscriptionHolder {
        var cancellables = Set<AnyCancellable>()
    }
    @State private var subscriptionHolder = SubscriptionHolder()

    // Tag order persistence
    private let tagOrderKey = "tagOrderPreference"

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            chipRow
        }
        .frame(height: 46)
        .scrollClipDisabled()
        .background(Color.clear)
        .onAppear {
            loadTags()
            calculateItemCounts()
            updateContentTypeCounts()
            setupSubscriptions()
        }
        .onDisappear {
            subscriptionHolder.cancellables.removeAll()
            saveTagOrder()
        }
        .onChange(of: viewModel.items.count) { _, _ in
            updateContentTypeCounts()
            calculateItemCounts()
        }
    }

    @ViewBuilder
    private var chipRow: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 8) {
                chipRowContent
            }
        } else {
            chipRowContent
        }
    }

    private var chipRowContent: some View {
        HStack(spacing: 8) {
                // "Clipboard History" chip to show all items
                clipboardHistoryChip

                // Divider
                divider

                // Content type filter chips (Power Search)
                contentTypeChips

                // Section divider — visually separates type filters from user tags
                sectionDivider

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
                    .id("\(tag.id)-\(tag.color.rawValue)")  // Force re-render when color changes
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

                // Always-visible search field
                ExpandableSearchBar(
                    searchText: $searchText,
                    placeholder: "Search clipboard...",
                    onSearch: performSearch
                )
            }
            .padding(.horizontal, 16)
    }

    // MARK: - Clipboard History Chip

    private var clipboardHistoryChip: some View {
        let isSelected = selectedTagIds.isEmpty && selectedContentType == nil

        return Button(action: clearAllFilters) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium))

                Text("Clipboard History")
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
        }
        .buttonStyle(.toolbarChip(isSelected: isSelected, tint: .accentColor))
    }

    // MARK: - Content Type Filter Chips

    private var contentTypeChips: some View {
        ForEach(activeContentTypes) { filter in
            Button {
                toggleContentType(filter)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: filter.icon)
                        .font(.system(size: 11, weight: .medium))
                    Text(filter.label)
                        .font(.system(size: 12, weight: isContentTypeSelected(filter) ? .semibold : .medium))
                    // Show count when selected
                    if isContentTypeSelected(filter) {
                        Text("\(contentTypeCount(filter))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
            }
            .buttonStyle(.toolbarChip(
                isSelected: isContentTypeSelected(filter),
                tint: .secondary
            ))
        }
    }

    /// Show filter chips for content types present in the full (unfiltered) item list.
    /// Uses allItemTypes which is cached on appear / item changes, so tag filtering
    /// (which replaces viewModel.items) doesn't make chips disappear.
    private var activeContentTypes: [ContentTypeFilter] {
        ContentTypeFilter.filters.filter { filter in
            !filter.matchTypes.isDisjoint(with: allItemTypes)
        }
    }

    private func isContentTypeSelected(_ filter: ContentTypeFilter) -> Bool {
        selectedContentType == filter.id
    }

    private func contentTypeCount(_ filter: ContentTypeFilter) -> Int {
        contentTypeCounts[filter.id] ?? 0
    }

    private func updateContentTypeCounts() {
        Task {
            do {
                let rawCounts = try await ClipboardService.shared.getContentTypeCounts()
                // Map raw content type counts to filter chip IDs
                var counts: [String: Int] = [:]
                for filter in ContentTypeFilter.filters {
                    counts[filter.id] = filter.matchTypes.reduce(0) { sum, type in
                        sum + (rawCounts[type] ?? 0)
                    }
                }
                contentTypeCounts = counts
                // Update allItemTypes from raw DB counts
                allItemTypes = Set(rawCounts.keys)
            } catch {
                NSLog("❌ Failed to load content type counts: \(error)")
            }
        }
    }

    private func toggleContentType(_ filter: ContentTypeFilter) {
        if isContentTypeSelected(filter) {
            selectedContentType = nil  // Deselect
        } else {
            // Clear tags and select content type (exclusive filters)
            selectedTagIds.removeAll()
            selectedContentType = filter.id
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Divider()
            .frame(height: 16)
    }

    /// A slightly thicker, more visible separator between content-type chips and tags
    private var sectionDivider: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
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
            // Single-select: clear content type and select only this tag
            selectedContentType = nil
            selectedTagIds = [tagId]
        }
    }

    private func clearAllFilters() {
        selectedTagIds.removeAll()
        selectedContentType = nil
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

        // Update local state immediately for instant visual feedback
        if let index = tags.firstIndex(where: { $0.id == tag.id }) {
            var updatedTag = tag
            updatedTag.update(color: newColor)
            tags[index] = updatedTag
            NSLog("🎨 Updated local tag color immediately")
        }

        // Then update database in background
        Task {
            var updatedTag = tag
            updatedTag.update(color: newColor)

            do {
                try await TagService.shared.updateTag(updatedTag)
                NSLog("✅ Color changed in database")
            } catch {
                NSLog("❌ Failed to change color: \(error)")
                // Revert on error
                if let index = tags.firstIndex(where: { $0.id == tag.id }) {
                    tags[index] = tag
                }
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

        // Move item to this tag (removes any existing tags first)
        viewModel.moveItemToTag(tagId: tag.id, itemId: itemId)

        // PERFORMANCE: Removed calculateItemCounts() - it's O(n*m) and too expensive
        // Item counts update when tags are loaded or modified via subscriptions

        // Visual feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

        // Optimistically update counts: decrement old tags, increment new tag
        if let item = viewModel.items.first(where: { $0.id == itemId }) {
            for oldTagId in item.tagIds where oldTagId != tag.id {
                tagItemCounts[oldTagId] = max(0, (tagItemCounts[oldTagId] ?? 0) - 1)
            }
        }
        tagItemCounts[tag.id] = (tagItemCounts[tag.id] ?? 0) + 1
    }

    // MARK: - Tag Reordering

    private func moveTag(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)
        // saveTagOrder() deferred to .onDisappear to avoid writes on every drag step
        NSLog("🔄 Reordered tags")
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
        Task {
            do {
                tagItemCounts = try await ClipboardService.shared.getTagItemCounts()
            } catch {
                NSLog("❌ Failed to load tag item counts: \(error)")
            }
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

        // Wire coordinate-based drag-to-tag drops.
        // TagDropCoordinator.draggingSession(_:endedAt:) calls this when a card is
        // dropped over a tag chip (detected via screen frame comparison, bypassing
        // GlassEffectContainer view-hierarchy routing).
        let vm = viewModel
        TagDropCoordinator.shared.onTagApplied = { itemId, tagId in
            NSLog("📌 TagDropCoordinator: moving item \(itemId) → tag \(tagId)")
            vm.moveItemToTag(tagId: tagId, itemId: itemId)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var viewModel = ClipboardViewModel()
        @State private var selectedTagIds: Set<UUID> = []
        @State private var selectedContentType: String? = nil
        @State private var searchText = ""

        var body: some View {
            VStack {
                TagFilterBarView(
                    viewModel: viewModel,
                    selectedTagIds: $selectedTagIds,
                    selectedContentType: $selectedContentType,
                    searchText: $searchText
                )
                .background(Color.gray.opacity(0.1))

                Spacer()

                Text("Selected tags: \(selectedTagIds.count)")
                    .foregroundStyle(.secondary)
            }
            .frame(height: 200)
        }
    }

    return PreviewWrapper()
}
