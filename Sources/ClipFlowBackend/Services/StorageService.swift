import Foundation
import ClipFlowCore

// MARK: - Storage Service

@MainActor
public class StorageService {
    private let databaseManager: DatabaseManager
    private let cacheManager: CacheManager
    private let fileManager: FileManager
    private let performanceMonitor: PerformanceMonitor

    // Storage statistics
    private var totalItemsStored: Int = 0
    private var totalSizeBytes: Int64 = 0
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0

    public init(
        databaseManager: DatabaseManager = DatabaseManager.shared,
        cacheManager: CacheManager = CacheManager.shared,
        performanceMonitor: PerformanceMonitor = PerformanceMonitor.shared
    ) {
        self.databaseManager = databaseManager
        self.cacheManager = cacheManager
        self.fileManager = FileManager.default
        self.performanceMonitor = performanceMonitor
    }

    // MARK: - Item Operations

    public func saveItem(_ item: ClipboardItem) async throws {
        try await performanceMonitor.measure(operation: "save_item") {
            // Check for duplicates first
            if await itemExists(hash: item.metadata.hash) {
                return
            }

            // Store large content to disk if needed
            var modifiedItem = item
            if let largeContentPath = await storeLargeContent(item) {
                modifiedItem = updateItemWithContentPath(item, path: largeContentPath)
            }

            // Save to database
            try await databaseManager.saveItem(modifiedItem)

            // Cache the item
            await cacheManager.cacheItem(modifiedItem, hash: modifiedItem.metadata.hash)

            // Update statistics
            totalItemsStored += 1
            totalSizeBytes += item.metadata.size

            // Log performance
            await databaseManager.logPerformanceMetric(
                operation: "save_item",
                duration: 0, // Would be measured by performanceMonitor
                memoryUsage: item.metadata.size
            )
        }
    }

    public func getItem(id: UUID) async throws -> ClipboardItem? {
        return try await performanceMonitor.measure(operation: "get_item") {
            // Check cache first
            if let cachedItem = await cacheManager.getItem(id: id) {
                cacheHits += 1

                // Update access time
                var item = cachedItem
                item.timestamps.markAccessed()
                try? await databaseManager.updateItem(item)

                return item
            }

            cacheMisses += 1

            // Load from database
            guard var item = try await databaseManager.getItem(id: id) else {
                return nil
            }

            // Load large content from disk if needed
            item = await loadLargeContent(item)

            // Update access time
            item.timestamps.markAccessed()
            try await databaseManager.updateItem(item)

            // Cache for future access
            await cacheManager.cacheItem(item, hash: item.metadata.hash)

            return item
        }
    }

    public func getItems(
        limit: Int = 100,
        offset: Int = 0,
        filter: ItemFilter? = nil
    ) async throws -> [ClipboardItem] {
        return try await performanceMonitor.measure(operation: "get_items") {
            let items = try await databaseManager.getItems(limit: limit, offset: offset, filter: filter)

            // Load large content for items that need it
            var loadedItems: [ClipboardItem] = []
            for var item in items {
                item = await loadLargeContent(item)
                loadedItems.append(item)

                // Cache frequently accessed items
                if item.isPinned || item.isFavorite {
                    await cacheManager.cacheItem(item, hash: item.metadata.hash)
                }
            }

            return loadedItems
        }
    }

    public func searchItems(query: String, limit: Int = 50) async throws -> [ClipboardItem] {
        return try await performanceMonitor.measure(operation: "search_items") {
            let items = try await databaseManager.searchItems(query: query, limit: limit)

            // Load large content and cache search results
            var searchResults: [ClipboardItem] = []
            for var item in items {
                item = await loadLargeContent(item)
                searchResults.append(item)
                await cacheManager.cacheItem(item, hash: item.metadata.hash)
            }

            return searchResults
        }
    }

    public func updateItem(_ item: ClipboardItem) async throws {
        try await performanceMonitor.measure(operation: "update_item") {
            var updatedItem = item
            updatedItem.timestamps.markModified()

            // Update in database
            try await databaseManager.updateItem(updatedItem)

            // Update cache
            await cacheManager.cacheItem(updatedItem, hash: updatedItem.metadata.hash)
        }
    }

    public func deleteItems(ids: [UUID], permanent: Bool = false) async throws {
        try await performanceMonitor.measure(operation: "delete_items") {
            if permanent {
                // Remove from cache
                for id in ids {
                    await cacheManager.removeItem(id: id)
                }

                // Remove large content files
                for id in ids {
                    if let item = try await databaseManager.getItem(id: id) {
                        await removeLargeContent(item)
                    }
                }
            }

            // Delete from database
            try await databaseManager.deleteItems(ids: ids, permanent: permanent)
        }
    }

    // MARK: - Collection Operations

    public func saveCollection(_ collection: Collection) async throws {
        try await performanceMonitor.measure(operation: "save_collection") {
            try await databaseManager.saveCollection(collection)
            await cacheManager.cacheCollection(collection)
        }
    }

    public func getCollections() async throws -> [Collection] {
        return try await performanceMonitor.measure(operation: "get_collections") {
            let collections = try await databaseManager.getCollections()

            // Cache collections
            for collection in collections {
                await cacheManager.cacheCollection(collection)
            }

            return collections
        }
    }

    // MARK: - Storage Statistics

    public func getStorageStatistics() async -> StorageStatistics {
        let advancedCacheStats = await cacheManager.getAdvancedStatistics()
        let databaseSize = await getDatabaseSize()
        let largeContentSize = await getLargeContentSize()

        // Convert AdvancedCacheStatistics to CacheStatistics
        let cacheStats = CacheStatistics(
            itemCount: advancedCacheStats.memoryItems + advancedCacheStats.diskItems,
            collectionCount: 0, // Collections not tracked separately
            memoryUsageBytes: advancedCacheStats.memoryUsageBytes,
            maxMemoryBytes: advancedCacheStats.maxMemoryBytes,
            hitRate: advancedCacheStats.overallHitRate,
            totalHits: advancedCacheStats.totalHits,
            totalMisses: advancedCacheStats.totalMisses,
            totalEvictions: advancedCacheStats.totalEvictions
        )

        return StorageStatistics(
            totalItemsStored: totalItemsStored,
            totalSizeBytes: totalSizeBytes,
            databaseSizeBytes: databaseSize,
            largeContentSizeBytes: largeContentSize,
            cacheHitRate: Double(cacheHits) / Double(max(cacheHits + cacheMisses, 1)),
            cacheStats: cacheStats
        )
    }

    // MARK: - Maintenance Operations

    public func cleanup() async throws {
        try await performanceMonitor.measure(operation: "cleanup") {
            // Clean up expired items
            try await databaseManager.cleanupExpiredItems()

            // Clean up orphaned large content files
            await cleanupOrphanedFiles()

            // Optimize cache
            await cacheManager.optimize()

            // Vacuum database
            try await databaseManager.vacuumDatabase()
        }
    }

    public func compactStorage() async throws {
        try await performanceMonitor.measure(operation: "compact_storage") {
            // Vacuum database
            try await databaseManager.vacuumDatabase()

            // Compress large content files
            await compressLargeContentFiles()

            // Optimize cache
            await cacheManager.optimize()
        }
    }

    // MARK: - Private Methods

    private func itemExists(hash: String) async -> Bool {
        do {
            let count = try await databaseManager.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_items WHERE hash = ? AND is_deleted = 0", arguments: [hash]) ?? 0
            }
            return count > 0
        } catch {
            return false
        }
    }

    private func storeLargeContent(_ item: ClipboardItem) async -> String? {
        // Store large content (> 1MB) to disk
        let threshold: Int64 = 1024 * 1024 // 1MB

        guard item.metadata.size > threshold else { return nil }

        let contentData: Data?
        switch item.content {
        case .image(let imageContent):
            contentData = imageContent.data
        case .richText(let richContent):
            contentData = richContent.rtfData
        case .file(_):
            // For files, we might store metadata or thumbnails
            contentData = nil
        default:
            contentData = nil
        }

        guard let data = contentData else { return nil }

        do {
            let contentDir = try getLargeContentDirectory()
            let contentPath = contentDir.appendingPathComponent("\(item.id.uuidString).data")
            try data.write(to: contentPath)
            return contentPath.path
        } catch {
            print("Failed to store large content: \(error)")
            return nil
        }
    }

    private func loadLargeContent(_ item: ClipboardItem) async -> ClipboardItem {
        // Check if item has large content stored separately
        let contentDir: URL
        do {
            contentDir = try getLargeContentDirectory()
        } catch {
            return item
        }

        let contentPath = contentDir.appendingPathComponent("\(item.id.uuidString).data")

        guard fileManager.fileExists(atPath: contentPath.path) else {
            return item
        }

        do {
            let data = try Data(contentsOf: contentPath)

            // Update item content with loaded data
            var updatedItem = item
            switch item.content {
            case .image(var imageContent):
                imageContent = ImageContent(
                    data: data,
                    format: imageContent.format,
                    dimensions: imageContent.dimensions,
                    thumbnailPath: imageContent.thumbnailPath,
                    colorPalette: imageContent.colorPalette,
                    hasTransparency: imageContent.hasTransparency
                )
                updatedItem = ClipboardItem(
                    id: item.id,
                    content: .image(imageContent),
                    metadata: item.metadata,
                    source: item.source,
                    timestamps: item.timestamps,
                    security: item.security,
                    tags: item.tags,
                    collectionIds: item.collectionIds,
                    isFavorite: item.isFavorite,
                    isPinned: item.isPinned,
                    isDeleted: item.isDeleted
                )
            default:
                break
            }

            return updatedItem
        } catch {
            print("Failed to load large content: \(error)")
            return item
        }
    }

    private func removeLargeContent(_ item: ClipboardItem) async {
        do {
            let contentDir = try getLargeContentDirectory()
            let contentPath = contentDir.appendingPathComponent("\(item.id.uuidString).data")

            if fileManager.fileExists(atPath: contentPath.path) {
                try fileManager.removeItem(at: contentPath)
            }
        } catch {
            print("Failed to remove large content: \(error)")
        }
    }

    private func updateItemWithContentPath(_ item: ClipboardItem, path: String) -> ClipboardItem {
        // In a real implementation, you might store the path in metadata
        // or modify the content to reference the file path
        return item
    }

    private func getLargeContentDirectory() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let contentDir = appSupport.appendingPathComponent("ClipFlow/LargeContent", isDirectory: true)
        try fileManager.createDirectory(at: contentDir, withIntermediateDirectories: true)

        return contentDir
    }

    private func getDatabaseSize() async -> Int64 {
        do {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )

            let dbPath = appSupport.appendingPathComponent("ClipFlow/ClipFlow.sqlite")
            let attributes = try fileManager.attributesOfItem(atPath: dbPath.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    private func getLargeContentSize() async -> Int64 {
        do {
            let contentDir = try getLargeContentDirectory()
            let enumerator = fileManager.enumerator(at: contentDir, includingPropertiesForKeys: [.fileSizeKey])

            var totalSize: Int64 = 0
            while let url = enumerator?.nextObject() as? URL {
                let resources = try url.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resources.fileSize ?? 0)
            }

            return totalSize
        } catch {
            return 0
        }
    }

    private func cleanupOrphanedFiles() async {
        do {
            let contentDir = try getLargeContentDirectory()
            let enumerator = fileManager.enumerator(at: contentDir, includingPropertiesForKeys: nil)

            while let url = enumerator?.nextObject() as? URL {
                let filename = url.lastPathComponent
                let itemId = String(filename.dropLast(5)) // Remove .data extension

                if let uuid = UUID(uuidString: itemId) {
                    // Check if item exists in database
                    let exists = try? await databaseManager.getItem(id: uuid) != nil
                    if exists != true {
                        try? fileManager.removeItem(at: url)
                    }
                }
            }
        } catch {
            print("Failed to cleanup orphaned files: \(error)")
        }
    }

    private func compressLargeContentFiles() async {
        // Implementation for compressing large content files
        // This could use compression algorithms or convert images to more efficient formats
        print("Compressing large content files...")
    }
}

// MARK: - Storage Statistics

public struct StorageStatistics {
    public let totalItemsStored: Int
    public let totalSizeBytes: Int64
    public let databaseSizeBytes: Int64
    public let largeContentSizeBytes: Int64
    public let cacheHitRate: Double
    public let cacheStats: CacheStatistics

    public var totalStorageBytes: Int64 {
        databaseSizeBytes + largeContentSizeBytes
    }

    public var averageItemSize: Double {
        totalItemsStored > 0 ? Double(totalSizeBytes) / Double(totalItemsStored) : 0
    }
}