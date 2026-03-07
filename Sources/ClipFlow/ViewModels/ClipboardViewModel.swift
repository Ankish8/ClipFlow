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

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private let clipboardService = ClipboardService.shared

    // Drag protection
    @ObservationIgnored private var isDragInProgress = false
    @ObservationIgnored private var itemsBackup: [ClipboardItem] = []

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
            // Known item (pin/unpin, edit, favorite, etc.) — update in-place so
            // its position is preserved. filteredItems' sort will move it if needed.
            items[idx] = item
            reconcilePreferredTint(for: item)
            itemHashSet.insert(item.metadata.hash)
            return
        }

        if itemHashSet.contains(item.metadata.hash) {
            // Same content, different ID (re-paste of existing text) — replace and promote.
            items.removeAll { $0.metadata.hash == item.metadata.hash }
        }

        // Genuinely new item — add at front.
        items.insert(item, at: 0)
        reconcilePreferredTint(for: item)
        itemIdSet.insert(item.id)
        itemHashSet.insert(item.metadata.hash)

        if items.count > 1000 {
            let removed = items.removeLast()
            itemIdSet.remove(removed.id)
            itemHashSet.remove(removed.metadata.hash)
        }
    }

    private func rebuildSets() {
        itemIdSet = Set(items.map(\.id))
        itemHashSet = Set(items.map(\.metadata.hash))
    }

    private func handleStatusUpdate(_ status: MonitorStatus) {
        switch status {
        case .monitoring:
            isLoading = false
            errorMessage = nil
        case .error(let error):
            errorMessage = error.localizedDescription
            isLoading = false
        case .stopped, .paused:
            isLoading = true
        }
    }

    private func loadInitialData() {
        Task {
            do {
                isLoading = true
                let history = try await clipboardService.getHistory(
                    offset: 0,
                    limit: 100,
                    filter: nil
                )

                // Only update items if not currently dragging
                if !isDragInProgress {
                    // Use freshly loaded history as the source of truth, then append any
                    // local-only items that were added after the fetch started.
                    var mergedItems = history
                    var mergedIds = Set(history.map(\.id))
                    var mergedHashes = Set(history.map(\.metadata.hash))
                    for existingItem in items
                        where !mergedIds.contains(existingItem.id)
                           && !mergedHashes.contains(existingItem.metadata.hash) {
                        mergedItems.append(existingItem)
                        mergedIds.insert(existingItem.id)
                        mergedHashes.insert(existingItem.metadata.hash)
                    }
                    items = mergedItems
                    rebuildSets()
                } else {
                    print("🛡️ Skipping data update during drag operation")
                }

                // Load statistics
                statistics = await clipboardService.getStatistics()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
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
        guard !query.isEmpty else {
            loadInitialData()
            return
        }

        Task {
            do {
                isLoading = true
                let results = try await clipboardService.search(
                    query: query,
                    scope: .all,
                    limit: 100
                )
                items = results
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
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
        Task {
            do {
                let moreItems = try await clipboardService.getHistory(
                    offset: items.count,
                    limit: 50,
                    filter: nil
                )
                items.append(contentsOf: moreItems)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Drag Protection

    private func setupDragProtection() {
        NotificationCenter.default.addObserver(
            forName: .startDragging,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDragStart()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .stopDragging,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDragEnd()
            }
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.itemsBackup.removeAll()
        }
    }

    // MARK: - Tag Management

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

        var updatedItems = items
        var updatedItem = updatedItems[index]
        if isAdding {
            updatedItem.tagIds.insert(tagId)
        } else {
            updatedItem.tagIds.remove(tagId)
        }
        updatedItems[index] = updatedItem
        items = updatedItems
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