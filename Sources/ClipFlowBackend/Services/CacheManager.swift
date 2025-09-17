import Foundation
import ClipFlowCore

// MARK: - Intelligent Cache Manager
/// High-performance multi-level caching system optimized for sub-100ms response times
/// Implements LRU eviction with 50MB memory and 500MB disk limits

public actor CacheManager {
    public static let shared = CacheManager()

    // MARK: - Multi-level cache storage
    private var memoryCache: [UUID: CachedItem] = [:]
    private var hashCache: [String: UUID] = [:] // Hash to UUID mapping for fast lookups
    private var collectionCache: [UUID: Collection] = [:]
    private var accessOrder: LinkedList<UUID> = LinkedList() // Optimized LRU

    // Disk cache
    private let diskCache: DiskCache
    private let cacheDirectory: URL

    // Cache configuration (as per research specifications)
    private let maxMemoryBytes: Int64 = 50 * 1024 * 1024 // 50MB memory limit
    private let maxDiskBytes: Int64 = 500 * 1024 * 1024 // 500MB disk limit
    private let maxItems: Int = 2000 // Increased for better performance
    private let ttlSeconds: TimeInterval = 3600 // 1 hour (longer for better hit rates)

    // Performance metrics
    private var memoryHits: Int = 0
    private var diskHits: Int = 0
    private var misses: Int = 0
    private var evictions: Int = 0
    private var diskEvictions: Int = 0

    private init() {
        // Initialize disk cache directory
        let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        self.cacheDirectory = documentsPath.appendingPathComponent("ClipFlow/cache")
        self.diskCache = DiskCache(directory: cacheDirectory, maxBytes: maxDiskBytes)

        Task {
            await setupCacheDirectory()
            await startCleanupTimer()
            await loadCacheMetadata()
        }
    }

    // MARK: - Multi-level Item Caching

    public func cacheItem(_ item: ClipboardItem, hash: String) async {
        let cachedItem = CachedItem(item: item, cachedAt: Date())

        // Update memory cache
        if let existingItem = memoryCache[item.id],
           let existingAccessNode = existingItem.accessNode {
            accessOrder.moveToTail(node: existingAccessNode)
            existingItem.accessNode = existingAccessNode
        } else {
            let node = accessOrder.append(item.id)
            cachedItem.accessNode = node
            memoryCache[item.id] = cachedItem
        }

        // Update hash mapping for fast lookups
        hashCache[hash] = item.id

        await enforceMemoryLimit()

        // Cache to disk asynchronously for persistence
        Task.detached { [diskCache] in
            await diskCache.store(item, forKey: item.id.uuidString)
        }
    }

    public func getCachedItem(for hash: String) async -> ClipboardItem? {
        // Check hash cache first
        guard let uuid = hashCache[hash] else {
            return await getItem(id: UUID()) // This will miss and check disk
        }

        return await getItem(id: uuid)
    }

    public func getItem(id: UUID) async -> ClipboardItem? {
        // L1 Cache: Memory cache (fastest)
        if let cachedItem = memoryCache[id] {
            // Check TTL
            if Date().timeIntervalSince(cachedItem.cachedAt) <= ttlSeconds {
                memoryHits += 1
                // Move to tail (most recently used)
                if let node = cachedItem.accessNode {
                    accessOrder.moveToTail(node: node)
                }
                return cachedItem.item
            } else {
                // Expired, remove from memory
                removeFromMemory(id: id)
            }
        }

        // L2 Cache: Disk cache (slower but persistent)
        if let item = await diskCache.retrieve(key: id.uuidString) {
            diskHits += 1
            // Promote back to memory cache
            await promoteToMemory(item: item)
            return item
        }

        misses += 1
        return nil
    }

    public func removeItem(id: UUID) async {
        removeFromMemory(id: id)
        await diskCache.remove(key: id.uuidString)
    }

    private func removeFromMemory(id: UUID) {
        if let cachedItem = memoryCache.removeValue(forKey: id),
           let node = cachedItem.accessNode {
            accessOrder.remove(node: node)
        }

        // Remove from hash cache
        hashCache = hashCache.filter { $0.value != id }
    }

    private func promoteToMemory(item: ClipboardItem) async {
        let cachedItem = CachedItem(item: item, cachedAt: Date())
        let node = accessOrder.append(item.id)
        cachedItem.accessNode = node
        memoryCache[item.id] = cachedItem

        await enforceMemoryLimit()
    }

    // MARK: - Collection Caching

    public func cacheCollection(_ collection: Collection) async {
        collectionCache[collection.id] = collection
    }

    public func getCollection(_ id: UUID) async -> Collection? {
        return collectionCache[id]
    }

    public func removeCollection(_ id: UUID) async {
        collectionCache.removeValue(forKey: id)
    }

    // MARK: - Cache Queries

    /// Get recent items from cache sorted by access order (most recent first)
    /// This is used as fallback when database is bypassed
    public func getRecentItems(limit: Int) async -> [ClipboardItem] {
        // Use the LRU access order to get most recent items
        let recentIds = accessOrder.getAllItems().reversed().prefix(limit)

        var items: [ClipboardItem] = []
        for id in recentIds {
            if let cachedItem = memoryCache[id] {
                items.append(cachedItem.item)
            }
        }

        return items
    }

    // MARK: - Advanced Cache Management

    private func enforceMemoryLimit() async {
        // Remove expired items first
        await removeExpiredItems()

        // Calculate current memory usage
        let currentMemory = getCurrentMemoryUsage()

        // Evict items if over limit using optimized LRU
        if currentMemory > maxMemoryBytes || memoryCache.count > maxItems {
            await evictLRUItems(targetMemory: maxMemoryBytes * 8 / 10) // Target 80% of max
        }
    }

    private func removeExpiredItems() async {
        let now = Date()
        var expiredIds: [UUID] = []

        for (id, cachedItem) in memoryCache {
            if now.timeIntervalSince(cachedItem.cachedAt) > ttlSeconds {
                expiredIds.append(id)
            }
        }

        for id in expiredIds {
            removeFromMemory(id: id)
        }
    }

    private func evictLRUItems(targetMemory: Int64) async {
        while getCurrentMemoryUsage() > targetMemory && !accessOrder.isEmpty {
            if let lruId = accessOrder.head?.value {
                removeFromMemory(id: lruId)
                evictions += 1
            } else {
                break
            }
        }
    }

    public func evictLeastRecentlyUsed(percentage: Double) async {
        let targetCount = Int(Double(memoryCache.count) * (1.0 - percentage))
        while memoryCache.count > targetCount && !accessOrder.isEmpty {
            if let lruId = accessOrder.head?.value {
                removeFromMemory(id: lruId)
                evictions += 1
            } else {
                break
            }
        }
    }

    private func getCurrentMemoryUsage() -> Int64 {
        return memoryCache.values.reduce(0) { total, cachedItem in
            total + cachedItem.item.metadata.size
        }
    }

    // MARK: - Cache Statistics and Monitoring

    public var hitRate: Double {
        let totalHits = memoryHits + diskHits
        let totalRequests = totalHits + misses
        return totalRequests > 0 ? Double(totalHits) / Double(totalRequests) : 0
    }

    public func getAdvancedStatistics() async -> AdvancedCacheStatistics {
        let memoryUsage = getCurrentMemoryUsage()
        let diskUsage = await diskCache.getCurrentSize()

        return AdvancedCacheStatistics(
            memoryItems: memoryCache.count,
            diskItems: await diskCache.getItemCount(),
            collectionCount: collectionCache.count,
            memoryUsageBytes: memoryUsage,
            diskUsageBytes: diskUsage,
            maxMemoryBytes: maxMemoryBytes,
            maxDiskBytes: maxDiskBytes,
            memoryHitRate: memoryHits > 0 ? Double(memoryHits) / Double(memoryHits + diskHits + misses) : 0,
            diskHitRate: diskHits > 0 ? Double(diskHits) / Double(memoryHits + diskHits + misses) : 0,
            overallHitRate: hitRate,
            totalMemoryHits: memoryHits,
            totalDiskHits: diskHits,
            totalMisses: misses,
            totalEvictions: evictions,
            diskEvictions: diskEvictions,
            averageItemSize: memoryCache.count > 0 ? Double(memoryUsage) / Double(memoryCache.count) : 0
        )
    }

    public func optimize() async {
        await removeExpiredItems()
        await enforceMemoryLimit()
        await diskCache.cleanup()
    }

    public func clearCache() async {
        memoryCache.removeAll()
        hashCache.removeAll()
        collectionCache.removeAll()
        accessOrder = LinkedList()
        memoryHits = 0
        diskHits = 0
        misses = 0
        evictions = 0
        await diskCache.clear()
    }

    // MARK: - Initialization Helpers

    private func setupCacheDirectory() async {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create cache directory: \(error)")
        }
    }

    private func loadCacheMetadata() async {
        // Load cache metadata from disk for persistence across app launches
        await diskCache.loadMetadata()
    }

    private func startCleanupTimer() async {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(300)) // 5 minutes
                await optimize()
            }
        }
    }

    // MARK: - Preloading and Warming

    public func preloadFrequentItems(limit: Int = 50) async {
        // Would query database for most frequently accessed items
        print("Preloading \(limit) frequent items...")
    }

    public func preloadPinnedItems() async {
        // Preload pinned items since they're likely to be accessed
        print("Preloading pinned items...")
    }

    public func warmCache() async {
        await preloadPinnedItems()
        await preloadFrequentItems()
    }
}

// MARK: - Enhanced Cached Item

private class CachedItem {
    let item: ClipboardItem
    let cachedAt: Date
    var accessNode: LinkedListNode<UUID>?

    init(item: ClipboardItem, cachedAt: Date) {
        self.item = item
        self.cachedAt = cachedAt
    }

    var age: TimeInterval {
        Date().timeIntervalSince(cachedAt)
    }
}

// MARK: - Optimized Linked List for LRU

private class LinkedListNode<T> {
    var value: T
    var prev: LinkedListNode<T>?
    var next: LinkedListNode<T>?

    init(value: T) {
        self.value = value
    }
}

private class LinkedList<T> {
    private(set) var head: LinkedListNode<T>?
    private(set) var tail: LinkedListNode<T>?
    private(set) var count = 0

    var isEmpty: Bool { head == nil }

    func append(_ value: T) -> LinkedListNode<T> {
        let node = LinkedListNode(value: value)

        if let tail = tail {
            tail.next = node
            node.prev = tail
            self.tail = node
        } else {
            head = node
            tail = node
        }

        count += 1
        return node
    }

    func remove(node: LinkedListNode<T>) {
        if node === head {
            head = node.next
        }
        if node === tail {
            tail = node.prev
        }

        node.prev?.next = node.next
        node.next?.prev = node.prev

        count -= 1
    }

    func moveToTail(node: LinkedListNode<T>) {
        guard node !== tail else { return }

        // Remove from current position
        if node === head {
            head = node.next
        }
        node.prev?.next = node.next
        node.next?.prev = node.prev

        // Add to tail
        node.prev = tail
        node.next = nil
        tail?.next = node
        tail = node

        if head == nil {
            head = node
        }
    }

    func getAllItems() -> [T] {
        var items: [T] = []
        var current = head
        while let node = current {
            items.append(node.value)
            current = node.next
        }
        return items
    }
}

// MARK: - High-Performance Disk Cache

private actor DiskCache {
    private let directory: URL
    private let maxBytes: Int64
    private var currentSize: Int64 = 0
    private var itemCount: Int = 0

    init(directory: URL, maxBytes: Int64) {
        self.directory = directory
        self.maxBytes = maxBytes
    }

    func store(_ item: ClipboardItem, forKey key: String) async {
        do {
            let data = try JSONEncoder().encode(item)
            let fileURL = directory.appendingPathComponent(key)

            // Check if file exists and remove from size calculation
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let existingSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0
                currentSize -= existingSize
            } else {
                itemCount += 1
            }

            try data.write(to: fileURL)
            currentSize += Int64(data.count)

            await enforceCapacity()
        } catch {
            print("Failed to store to disk cache: \(error)")
        }
    }

    func retrieve(key: String) async -> ClipboardItem? {
        do {
            let fileURL = directory.appendingPathComponent(key)
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(ClipboardItem.self, from: data)
        } catch {
            return nil
        }
    }

    func remove(key: String) async {
        do {
            let fileURL = directory.appendingPathComponent(key)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let size = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0
                try FileManager.default.removeItem(at: fileURL)
                currentSize -= size
                itemCount -= 1
            }
        } catch {
            print("Failed to remove from disk cache: \(error)")
        }
    }

    func getCurrentSize() async -> Int64 {
        return currentSize
    }

    func getItemCount() async -> Int {
        return itemCount
    }

    func loadMetadata() async {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            currentSize = 0
            itemCount = fileURLs.count

            for url in fileURLs {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                currentSize += Int64(resourceValues.fileSize ?? 0)
            }
        } catch {
            currentSize = 0
            itemCount = 0
        }
    }

    func cleanup() async {
        await enforceCapacity()
        await removeOldFiles()
    }

    func clear() async {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for url in fileURLs {
                try FileManager.default.removeItem(at: url)
            }
            currentSize = 0
            itemCount = 0
        } catch {
            print("Failed to clear disk cache: \(error)")
        }
    }

    private func enforceCapacity() async {
        guard currentSize > maxBytes else { return }

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            )

            // Sort by modification date (oldest first)
            let sortedFiles = fileURLs.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 < date2
            }

            // Remove oldest files until under capacity
            for fileURL in sortedFiles {
                guard currentSize > maxBytes * 8 / 10 else { break } // Target 80% of max

                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                let size = Int64(resourceValues.fileSize ?? 0)

                try FileManager.default.removeItem(at: fileURL)
                currentSize -= size
                itemCount -= 1
            }
        } catch {
            print("Failed to enforce disk cache capacity: \(error)")
        }
    }

    private func removeOldFiles() async {
        let expirationDate = Date().addingTimeInterval(-7 * 24 * 3600) // 7 days old

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            )

            for fileURL in fileURLs {
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                if let modDate = resourceValues.contentModificationDate, modDate < expirationDate {
                    let size = Int64(resourceValues.fileSize ?? 0)
                    try FileManager.default.removeItem(at: fileURL)
                    currentSize -= size
                    itemCount -= 1
                }
            }
        } catch {
            print("Failed to remove old files: \(error)")
        }
    }
}

// MARK: - Advanced Cache Statistics

public struct AdvancedCacheStatistics: Sendable {
    public let memoryItems: Int
    public let diskItems: Int
    public let collectionCount: Int
    public let memoryUsageBytes: Int64
    public let diskUsageBytes: Int64
    public let maxMemoryBytes: Int64
    public let maxDiskBytes: Int64
    public let memoryHitRate: Double
    public let diskHitRate: Double
    public let overallHitRate: Double
    public let totalMemoryHits: Int
    public let totalDiskHits: Int
    public let totalMisses: Int
    public let totalEvictions: Int
    public let diskEvictions: Int
    public let averageItemSize: Double

    public var memoryUtilization: Double {
        maxMemoryBytes > 0 ? Double(memoryUsageBytes) / Double(maxMemoryBytes) : 0
    }

    public var diskUtilization: Double {
        maxDiskBytes > 0 ? Double(diskUsageBytes) / Double(maxDiskBytes) : 0
    }

    public var totalHits: Int {
        totalMemoryHits + totalDiskHits
    }

    public var totalRequests: Int {
        totalHits + totalMisses
    }
}

// MARK: - Legacy Cache Statistics (for compatibility)

public struct CacheStatistics: Sendable {
    public let itemCount: Int
    public let collectionCount: Int
    public let memoryUsageBytes: Int64
    public let maxMemoryBytes: Int64
    public let hitRate: Double
    public let totalHits: Int
    public let totalMisses: Int
    public let totalEvictions: Int

    public var memoryUtilization: Double {
        maxMemoryBytes > 0 ? Double(memoryUsageBytes) / Double(maxMemoryBytes) : 0
    }

    public var averageItemSize: Double {
        itemCount > 0 ? Double(memoryUsageBytes) / Double(itemCount) : 0
    }
}