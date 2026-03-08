import SwiftUI
import Combine
import AppKit
import ClipFlowCore
import ClipFlowAPI
import ClipFlowBackend

@MainActor @Observable
class ClipboardViewModel {
    var items: [ClipboardItem] = []
    var isLoading = false
    var errorMessage: String?
    var statistics: ClipboardStatistics?
    var preferredTintTagIDs: [UUID: UUID] = [:]

    // Pagination state
    var activeFilter: ItemFilter? = nil
    var totalFilteredCount: Int = 0
    var hasMore: Bool = true
    private let pageSize = 50

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private let clipboardService = ClipboardService.shared
    @ObservationIgnored private var filterDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var pageLoadTask: Task<Void, Never>?
    /// Monotonically increasing counter to discard stale query results.
    @ObservationIgnored private var filterGeneration: Int = 0

    // Drag protection
    @ObservationIgnored private var isDragInProgress = false
    @ObservationIgnored private var itemsBackup: [ClipboardItem] = []
    @ObservationIgnored nonisolated(unsafe) private var dragObservers: [NSObjectProtocol] = []

    // O(1) duplicate detection — kept in sync with items array
    @ObservationIgnored private var itemIdSet = Set<UUID>()
    @ObservationIgnored private var itemHashSet = Set<String>()

    func initialize() {
        print("🚀 ViewModel initializing...")
        setupSubscriptions()
        loadInitialData()

        // Subscribe to drag notifications for data protection
        setupDragProtection()
    }

    private func setupSubscriptions() {
        // Subscribe to real-time clipboard updates
        clipboardService.itemUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newItem in
                self?.handleNewItem(newItem)
            }
            .store(in: &cancellables)

        // Subscribe to errors
        clipboardService.errors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error.localizedDescription
            }
            .store(in: &cancellables)

        // Subscribe to status updates
        clipboardService.statusUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleStatusUpdate(status)
            }
            .store(in: &cancellables)
    }

    private func handleNewItem(_ item: ClipboardItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            let existing = items[idx]
            // If the timestamp changed, this is a re-copy (duplicate bumped to top).
            // Remove from old position and fall through to insert at front.
            if existing.timestamps.createdAt != item.timestamps.createdAt {
                items.remove(at: idx)
            } else {
                // Same timestamp — in-place update (pin/edit/favorite/tag change).
                items[idx] = item
                reconcilePreferredTint(for: item)
                itemHashSet.insert(item.metadata.hash)
                return
            }
        }

        if itemHashSet.contains(item.metadata.hash) {
            // Same content, different ID (re-paste of existing text) — replace and promote.
            items.removeAll { $0.metadata.hash == item.metadata.hash }
        }

        // If a filter is active, only insert if the item matches
        if let filter = activeFilter {
            guard itemMatchesFilter(item, filter: filter) else { return }
        }

        // Genuinely new item — add at front (after pinned items if not pinned).
        if item.isPinned {
            items.insert(item, at: 0)
        } else {
            // Insert after the last pinned item
            let insertIndex = items.firstIndex(where: { !$0.isPinned }) ?? items.count
            items.insert(item, at: insertIndex)
        }
        reconcilePreferredTint(for: item)
        itemIdSet.insert(item.id)
        itemHashSet.insert(item.metadata.hash)
        totalFilteredCount += 1

        // Trim tail to keep memory bounded (keep ~200 items max in memory)
        let memoryLimit = 200
        while items.count > memoryLimit {
            let removed = items.removeLast()
            itemIdSet.remove(removed.id)
            itemHashSet.remove(removed.metadata.hash)
            hasMore = true  // We trimmed, so there's more in DB
        }
    }

    /// Check if an item matches the current active filter (client-side check for new items).
    private func itemMatchesFilter(_ item: ClipboardItem, filter: ItemFilter) -> Bool {
        if let contentTypes = filter.contentTypes, !contentTypes.isEmpty {
            guard contentTypes.contains(item.content.contentType) else { return false }
        }
        if let tagIds = filter.tagIds, !tagIds.isEmpty {
            guard !item.tagIds.isDisjoint(with: tagIds) else { return false }
        }
        if let searchQuery = filter.searchQuery, !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            let textMatch = item.content.displayText.lowercased().contains(q)
            let appMatch = item.source.applicationName?.lowercased().contains(q) ?? false
            guard textMatch || appMatch else { return false }
        }
        if let isPinned = filter.isPinned {
            guard item.isPinned == isPinned else { return false }
        }
        if let isFavorite = filter.isFavorite {
            guard item.isFavorite == isFavorite else { return false }
        }
        return true
    }

    private func rebuildSets() {
        itemIdSet = Set(items.map(\.id))
        itemHashSet = Set(items.map(\.metadata.hash))
    }

    private func handleStatusUpdate(_ status: MonitorStatus) {
        switch status {
        case .monitoring:
            if isLoading != false { isLoading = false }
            if errorMessage != nil { errorMessage = nil }
        case .error(let error):
            let desc = error.localizedDescription
            if errorMessage != desc { errorMessage = desc }
            if isLoading != false { isLoading = false }
        case .stopped, .paused:
            if isLoading != true { isLoading = true }
        }
    }

    private func loadInitialData() {
        loadPage(reset: true)
    }

    /// Load a page of items from DB with current activeFilter.
    /// `reset: true` replaces items (new filter). `reset: false` appends (infinite scroll).
    func loadPage(reset: Bool) {
        // Cancel any in-flight page load so we don't apply stale results
        pageLoadTask?.cancel()

        // Capture a generation number so we can discard results from superseded queries.
        // This guards against the race where a completed stale query overwrites `items`
        // just before cancel() is processed.
        filterGeneration += 1
        let myGeneration = filterGeneration

        pageLoadTask = Task {
            do {
                isLoading = true
                let offset = reset ? 0 : items.count
                let filter = activeFilter.map { convertToHistoryFilter($0) }
                let page = try await clipboardService.getHistory(
                    offset: offset,
                    limit: pageSize,
                    filter: filter
                )

                // Discard if a newer loadPage was triggered while we were awaiting
                guard !Task.isCancelled, myGeneration == filterGeneration else { return }

                if !isDragInProgress {
                    if reset {
                        NSLog("📊 loadPage: replacing items. old=\(items.count), new=\(page.count), filter=\(String(describing: filter)), gen=\(myGeneration)")
                        items = page
                        rebuildSets()
                    } else {
                        // Append, deduplicating
                        for item in page where !itemIdSet.contains(item.id) {
                            items.append(item)
                            itemIdSet.insert(item.id)
                            itemHashSet.insert(item.metadata.hash)
                        }
                    }
                    hasMore = page.count >= pageSize
                    totalFilteredCount = try await clipboardService.getItemCount(filter: filter)
                }

                guard !Task.isCancelled, myGeneration == filterGeneration else { return }

                if reset {
                    statistics = await clipboardService.getStatistics()
                }
                isLoading = false
            } catch {
                if !Task.isCancelled, myGeneration == filterGeneration {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    /// Build and apply a filter. Immediately triggers a page load (cancelling any in-flight one).
    /// `contentTypes` should be the resolved set of content type strings (e.g., ["text", "richText"]).
    func applyFilter(
        tagIds: Set<UUID>? = nil,
        contentTypes: [String]? = nil,
        searchQuery: String? = nil
    ) {
        let newFilter: ItemFilter?
        let hasFilter = !(tagIds?.isEmpty ?? true)
            || !(contentTypes?.isEmpty ?? true)
            || !(searchQuery?.isEmpty ?? true)

        if hasFilter {
            newFilter = ItemFilter(
                contentTypes: (contentTypes?.isEmpty ?? true) ? nil : contentTypes,
                tagIds: (tagIds?.isEmpty ?? true) ? nil : tagIds,
                searchQuery: (searchQuery?.isEmpty ?? true) ? nil : searchQuery
            )
        } else {
            newFilter = nil
        }

        activeFilter = newFilter
        loadPage(reset: true)
    }

    /// Convert ItemFilter to HistoryFilter for the service layer.
    private func convertToHistoryFilter(_ filter: ItemFilter) -> HistoryFilter {
        HistoryFilter(
            contentTypes: filter.contentTypes,
            applications: filter.applications,
            dateRange: filter.dateRange,
            isFavorite: filter.isFavorite,
            isPinned: filter.isPinned,
            tagIds: filter.tagIds,
            searchQuery: filter.searchQuery
        )
    }

    // MARK: - User Actions

    func togglePin(for item: ClipboardItem) {
        Task {
            do {
                try await clipboardService.togglePin(itemId: item.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleFavorite(for item: ClipboardItem) {
        Task {
            do {
                try await clipboardService.toggleFavorite(itemId: item.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteItem(_ item: ClipboardItem) {
        Task {
            do {
                try await clipboardService.deleteItems(ids: [item.id])
                items.removeAll { $0.id == item.id }
                itemIdSet.remove(item.id)
                itemHashSet.remove(item.metadata.hash)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func pasteItem(_ item: ClipboardItem, transform: TransformAction? = nil) {
        Task {
            do {
                try await clipboardService.paste(item, transform: transform)
                SoundManager.shared.play(.paste)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func pasteMultipleItems(_ items: [ClipboardItem]) {
        Task {
            do {
                try await clipboardService.pasteMultiple(items)
                SoundManager.shared.play(.paste)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }


    // MARK: - Search and Filtering

    func filteredItems(for searchText: String) -> [ClipboardItem] {
        guard !searchText.isEmpty else { return items }

        return items.filter { item in
            // Search in content
            let contentMatch = item.content.displayText.localizedCaseInsensitiveContains(searchText)

            // Search in source application
            let appMatch = item.source.applicationName?.localizedCaseInsensitiveContains(searchText) ?? false

            return contentMatch || appMatch
        }
    }

    func performFullTextSearch(_ query: String) {
        if query.isEmpty {
            applyFilter(searchQuery: nil)
        } else {
            applyFilter(searchQuery: query)
        }
    }

    // MARK: - Data Management

    func refreshData() {
        if !isDragInProgress {
            loadInitialData()
        } else {
            print("🛡️ Skipping refresh during drag operation")
        }
    }

    func clearHistory() {
        // Don't clear during drag
        guard !isDragInProgress else {
            print("🛡️ Preventing clear history during drag operation")
            return
        }

        Task {
            do {
                try await clipboardService.clearHistory(olderThan: nil)
                items.removeAll()
                itemIdSet.removeAll()
                itemHashSet.removeAll()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore() {
        guard hasMore, !isLoading else { return }
        loadPage(reset: false)
    }

    // MARK: - Drag Protection

    private func setupDragProtection() {
        let obs1 = NotificationCenter.default.addObserver(
            forName: .startDragging,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDragStart()
            }
        }
        dragObservers.append(obs1)

        let obs2 = NotificationCenter.default.addObserver(
            forName: .stopDragging,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDragEnd()
            }
        }
        dragObservers.append(obs2)
    }

    deinit {
        dragObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func handleDragStart() {
        print("🛡️ Drag started - backing up \(items.count) items")
        isDragInProgress = true
        itemsBackup = items // Backup current items
    }

    private func handleDragEnd() {
        print("🛡️ Drag ended - checking data integrity")
        isDragInProgress = false

        // If items were cleared during drag, restore from backup
        if items.isEmpty && !itemsBackup.isEmpty {
            print("🔧 Data was lost during drag - restoring \(itemsBackup.count) items")
            items = itemsBackup
            rebuildSets()
        }

        // Clear backup after a short delay
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            self.itemsBackup.removeAll()
        }
    }

    // MARK: - Tag Management

    /// Move an item to a tag — removes all existing tags first (single-tag model).
    func moveItemToTag(tagId: UUID, itemId: UUID) {
        guard let item = item(withId: itemId) else { return }

        // Remove all existing tags locally first
        let existingTags = item.tagIds
        for oldTagId in existingTags {
            if oldTagId != tagId {
                removeTagFromItem(tagId: oldTagId, itemId: itemId)
            }
        }

        // Add the new tag (skips if already applied)
        addTagToItem(tagId: tagId, itemId: itemId)
    }

    func addTagToItem(tagId: UUID, itemId: UUID) {
        let alreadyTagged = item(withId: itemId)?.tagIds.contains(tagId) ?? false
        guard !alreadyTagged else {
            NSLog("⚠️ Skipping tag add for item \(itemId) because tag \(tagId) is already applied")
            return
        }

        preferredTintTagIDs[itemId] = tagId
        applyLocalTagChange(tagId: tagId, itemId: itemId, isAdding: true)

        Task {
            do {
                try await ClipFlowBackend.TagService.shared.tagItem(tagId: tagId, itemId: itemId)
            } catch {
                NSLog("❌ Failed to tag item \(itemId) with tag \(tagId): \(error.localizedDescription)")
                if preferredTintTagIDs[itemId] == tagId {
                    preferredTintTagIDs.removeValue(forKey: itemId)
                }
                applyLocalTagChange(tagId: tagId, itemId: itemId, isAdding: false)
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeTagFromItem(tagId: UUID, itemId: UUID) {
        let alreadyTagged = item(withId: itemId)?.tagIds.contains(tagId) ?? false
        guard alreadyTagged else {
            NSLog("⚠️ Skipping tag removal for item \(itemId) because tag \(tagId) is not applied")
            return
        }

        if preferredTintTagIDs[itemId] == tagId {
            preferredTintTagIDs.removeValue(forKey: itemId)
        }
        applyLocalTagChange(tagId: tagId, itemId: itemId, isAdding: false)

        Task {
            do {
                try await ClipFlowBackend.TagService.shared.untagItem(tagId: tagId, itemId: itemId)
            } catch {
                NSLog("❌ Failed to remove tag \(tagId) from item \(itemId): \(error.localizedDescription)")
                applyLocalTagChange(tagId: tagId, itemId: itemId, isAdding: true)
                errorMessage = error.localizedDescription
            }
        }
    }

    func getTagsForItem(itemId: UUID) async -> [Tag] {
        do {
            return try await ClipFlowBackend.TagService.shared.getTagsForItem(itemId: itemId)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // MARK: - Tag Filtering

    /// Whether the current items array was loaded via tag filter (DB-backed).
    var isTagFiltered: Bool {
        activeFilter?.tagIds != nil
    }

    func filteredItems(byTags tagIds: Set<UUID>) -> [ClipboardItem] {
        guard !tagIds.isEmpty else { return items }
        return items.filter { !$0.tagIds.isDisjoint(with: tagIds) }
    }

    func preferredTintTagId(for itemId: UUID, among tagIds: Set<UUID>) -> UUID? {
        guard let preferredTagId = preferredTintTagIDs[itemId],
              tagIds.contains(preferredTagId) else {
            return nil
        }
        return preferredTagId
    }

    private func item(withId itemId: UUID) -> ClipboardItem? {
        items.first { $0.id == itemId }
    }

    private func reconcilePreferredTint(for item: ClipboardItem) {
        guard let preferredTagId = preferredTintTagIDs[item.id],
              !item.tagIds.contains(preferredTagId) else {
            return
        }
        preferredTintTagIDs.removeValue(forKey: item.id)
    }

    private func applyLocalTagChange(tagId: UUID, itemId: UUID, isAdding: Bool) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            NSLog("❌ Unable to apply local tag change because item \(itemId) is not in memory")
            return
        }

        if isAdding {
            items[index].tagIds.insert(tagId)
        } else {
            items[index].tagIds.remove(tagId)
        }
    }

    // MARK: - Copy to Clipboard (no paste)

    /// Write item content to NSPasteboard without triggering paste.
    func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.content {
        case .text(let c):     pb.setString(c.plainText, forType: .string)
        case .richText(let c): pb.setString(c.plainTextFallback, forType: .string)
        case .link(let c):     pb.setString(c.url.absoluteString, forType: .string)
        case .code(let c):     pb.setString(c.code, forType: .string)
        case .color(let c):    pb.setString(c.hexValue, forType: .string)
        case .snippet(let c):  pb.setString(c.content, forType: .string)
        case .image(let c):
            if let img = NSImage(data: c.data) { pb.writeObjects([img]) }
        case .file(let c):
            pb.writeObjects(c.urls as [NSURL])
        case .multiple(let c):
            for sub in c.items {
                if case .text(let t) = sub { pb.setString(t.plainText, forType: .string); break }
            }
        }
    }

    // MARK: - Edit Item Text

    /// Update the plain-text content of a text-type item. Persists to DB and updates local cache.
    func updateItemText(_ item: ClipboardItem, newText: String) {
        guard case .text(let old) = item.content else { return }
        let newContent = ClipboardContent.text(
            TextContent(plainText: newText, encoding: old.encoding, language: old.language,
                        isEmail: old.isEmail, isPhoneNumber: old.isPhoneNumber, isURL: old.isURL)
        )
        let updated = ClipboardItem(
            id: item.id, content: newContent,
            metadata: ItemMetadata.generate(for: newContent),
            source: item.source, timestamps: item.timestamps,
            security: item.security, collectionIds: item.collectionIds,
            tagIds: item.tagIds, isFavorite: item.isFavorite,
            isPinned: item.isPinned, isDeleted: item.isDeleted
        )
        Task {
            do {
                try await clipboardService.updateItemContent(updated)
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx] = updated
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Update the code content of a code-type item. Preserves language/metadata.
    func updateItemCode(_ item: ClipboardItem, newText: String) {
        guard case .code(let old) = item.content else { return }
        let newContent = ClipboardContent.code(
            CodeContent(code: newText, language: old.language,
                        syntaxHighlightedData: old.syntaxHighlightedData,
                        repository: old.repository)
        )
        let updated = ClipboardItem(
            id: item.id, content: newContent,
            metadata: ItemMetadata.generate(for: newContent),
            source: item.source, timestamps: item.timestamps,
            security: item.security, collectionIds: item.collectionIds,
            tagIds: item.tagIds, isFavorite: item.isFavorite,
            isPinned: item.isPinned, isDeleted: item.isDeleted
        )
        Task {
            do {
                try await clipboardService.updateItemContent(updated)
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx] = updated
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Update the content of a snippet-type item. Preserves metadata.
    func updateItemSnippet(_ item: ClipboardItem, newText: String) {
        guard case .snippet(let old) = item.content else { return }
        let newContent = ClipboardContent.snippet(
            SnippetContent(id: old.id, title: old.title, content: newText,
                           placeholders: old.placeholders, keyword: old.keyword,
                           category: old.category, usageCount: old.usageCount)
        )
        let updated = ClipboardItem(
            id: item.id, content: newContent,
            metadata: ItemMetadata.generate(for: newContent),
            source: item.source, timestamps: item.timestamps,
            security: item.security, collectionIds: item.collectionIds,
            tagIds: item.tagIds, isFavorite: item.isFavorite,
            isPinned: item.isPinned, isDeleted: item.isDeleted
        )
        Task {
            do {
                try await clipboardService.updateItemContent(updated)
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx] = updated
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Update the URL (and optionally title) of a link-type item.
    func updateItemLink(_ item: ClipboardItem, newURLString: String, newTitle: String?) {
        guard case .link(let old) = item.content,
              let newURL = URL(string: newURLString.trimmingCharacters(in: .whitespaces)) else { return }
        let newContent = ClipboardContent.link(
            LinkContent(url: newURL, title: newTitle, description: old.description,
                        faviconData: old.faviconData, previewImageData: old.previewImageData)
        )
        let updated = ClipboardItem(
            id: item.id, content: newContent,
            metadata: ItemMetadata.generate(for: newContent),
            source: item.source, timestamps: item.timestamps,
            security: item.security, collectionIds: item.collectionIds,
            tagIds: item.tagIds, isFavorite: item.isFavorite,
            isPinned: item.isPinned, isDeleted: item.isDeleted
        )
        Task {
            do {
                try await clipboardService.updateItemContent(updated)
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx] = updated
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Update a link item's metadata (title, description, favicon) after enrichment.
    func updateLinkMetadata(_ item: ClipboardItem, title: String?, description: String?, faviconData: Data?, previewImageData: Data? = nil) {
        guard case .link(let old) = item.content else { return }
        let newContent = ClipboardContent.link(
            LinkContent(url: old.url,
                        title: title ?? old.title,
                        description: description ?? old.description,
                        faviconData: faviconData ?? old.faviconData,
                        previewImageData: previewImageData ?? old.previewImageData)
        )
        let updated = ClipboardItem(
            id: item.id, content: newContent,
            metadata: ItemMetadata.generate(for: newContent),
            source: item.source, timestamps: item.timestamps,
            security: item.security, collectionIds: item.collectionIds,
            tagIds: item.tagIds, isFavorite: item.isFavorite,
            isPinned: item.isPinned, isDeleted: item.isDeleted
        )
        Task {
            do {
                try await clipboardService.updateItemContent(updated)
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx] = updated
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Pin / Unpin

    /// Optimistically set pin state with immediate local update.
    /// Uses explicit set (not toggle) to avoid race with stale cache.
    func setPinned(_ pinned: Bool, for item: ClipboardItem) {
        NSLog("📌 VM.setPinned called: pinned=\(pinned) item.isPinned=\(item.isPinned)")
        guard item.isPinned != pinned else {
            NSLog("📌 VM.setPinned guard failed — already in desired state")
            return
        }
        // Optimistic update first so UI reflects change immediately
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            var updated = items[idx]
            updated.isPinned = pinned
            items[idx] = updated
            NSLog("📌 VM.setPinned optimistic update done, items[\(idx)].isPinned=\(items[idx].isPinned)")
        } else {
            NSLog("📌 VM.setPinned: item not found in items array!")
        }
        Task {
            do {
                try await clipboardService.setItemPinned(itemId: item.id, pinned: pinned)
            } catch {
                NSLog("❌ VM.setPinned error: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Custom Name (Rename)
    // Stored as @Observable so card headers re-render instantly on rename.
    // Persisted to UserDefaults for across-launch durability.

    private static let customNamesKey = "ClipFlow.customItemNames"

    // @Observable tracking: reads of customNames in SwiftUI body auto-register deps.
    var customNames: [String: String] = {
        (UserDefaults.standard.dictionary(forKey: customNamesKey) as? [String: String]) ?? [:]
    }()

    func customName(for itemId: UUID) -> String? {
        customNames[itemId.uuidString]
    }

    func setCustomName(_ name: String?, for itemId: UUID) {
        let key = itemId.uuidString
        if let n = name, !n.isEmpty {
            customNames[key] = n
        } else {
            customNames.removeValue(forKey: key)
        }
        // Persist for next launch
        UserDefaults.standard.set(customNames, forKey: Self.customNamesKey)
    }
}