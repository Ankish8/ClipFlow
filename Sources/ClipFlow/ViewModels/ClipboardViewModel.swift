import SwiftUI
import Combine
import AppKit
import ClipFlowCore
import ClipFlowAPI
import ClipFlowBackend

@MainActor
class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statistics: ClipboardStatistics?

    private var cancellables = Set<AnyCancellable>()
    private let clipboardService = ClipboardService.shared

    // Drag protection
    private var isDragInProgress = false
    private var itemsBackup: [ClipboardItem] = []

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
        // Remove duplicates by ID or hash, but KEEP the new item (it might have better classification)
        items.removeAll { existingItem in
            existingItem.id == item.id || existingItem.metadata.hash == item.metadata.hash
        }
        // Insert the NEW item at the beginning (it has the latest/correct classification)
        items.insert(item, at: 0)

        // Limit to reasonable number for performance
        if items.count > 1000 {
            items = Array(items.prefix(1000))
        }
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
                    // Merge history with existing items, preferring existing (newer/correct) items
                    var mergedItems: [ClipboardItem] = items
                    for historyItem in history {
                        // Only add if not already present (by ID or hash)
                        let isDuplicate = mergedItems.contains { existing in
                            existing.id == historyItem.id || existing.metadata.hash == historyItem.metadata.hash
                        }
                        if !isDuplicate {
                            mergedItems.append(historyItem)
                        }
                    }
                    items = mergedItems
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
        // Subscribe to start dragging notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("startDragging"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDragStart()
            }
        }

        // Subscribe to stop dragging notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("stopDragging"),
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
        }

        // Clear backup after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.itemsBackup.removeAll()
        }
    }

    // MARK: - Tag Management

    func addTagToItem(tagId: UUID, itemId: UUID) {
        Task {
            do {
                try await ClipFlowBackend.TagService.shared.tagItem(tagId: tagId, itemId: itemId)

                // Update local item
                if let index = items.firstIndex(where: { $0.id == itemId }) {
                    var updatedItem = items[index]
                    updatedItem.tagIds.insert(tagId)
                    items[index] = updatedItem
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeTagFromItem(tagId: UUID, itemId: UUID) {
        Task {
            do {
                try await ClipFlowBackend.TagService.shared.untagItem(tagId: tagId, itemId: itemId)

                // Update local item
                if let index = items.firstIndex(where: { $0.id == itemId }) {
                    var updatedItem = items[index]
                    updatedItem.tagIds.remove(tagId)
                    items[index] = updatedItem
                }
            } catch {
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

        return items.filter { item in
            // Item must have at least one of the selected tags
            !item.tagIds.intersection(tagIds).isEmpty
        }
    }
}