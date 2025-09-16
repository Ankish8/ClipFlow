import Foundation
import ClipFlowCore

// MARK: - Cache Manager

@MainActor
public class CacheManager {
    public static let shared = CacheManager()

    private var itemCache: [UUID: CachedItem] = [:]
    private var collectionCache: [UUID: Collection] = [:]
    private var accessOrder: [UUID] = [] // For LRU eviction

    // Cache configuration
    private let maxMemoryBytes: Int64 = 50 * 1024 * 1024 // 50MB
    private let maxItems: Int = 1000
    private let ttlSeconds: TimeInterval = 300 // 5 minutes

    // Statistics
    private var hits: Int = 0
    private var misses: Int = 0
    private var evictions: Int = 0

    private init() {
        // Start cleanup timer
        startCleanupTimer()
    }

    // MARK: - Item Caching

    public func cache(_ item: ClipboardItem) async {
        let cachedItem = CachedItem(item: item, cachedAt: Date())

        // Remove if already exists to update access order
        if itemCache[item.id] != nil {
            accessOrder.removeAll { $0 == item.id }
        }

        itemCache[item.id] = cachedItem
        accessOrder.append(item.id)

        await enforceMemoryLimit()
    }

    public func get(_ id: UUID) async -> ClipboardItem? {
        guard let cachedItem = itemCache[id] else {
            misses += 1
            return nil
        }

        // Check TTL
        if Date().timeIntervalSince(cachedItem.cachedAt) > ttlSeconds {
            itemCache.removeValue(forKey: id)
            accessOrder.removeAll { $0 == id }
            misses += 1
            return nil
        }

        hits += 1

        // Update access order (move to end)
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)

        return cachedItem.item
    }

    public func remove(_ id: UUID) async {
        itemCache.removeValue(forKey: id)
        accessOrder.removeAll { $0 == id }
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

    // MARK: - Cache Management

    private func enforceMemoryLimit() async {
        // Remove expired items first
        await removeExpiredItems()

        // Calculate current memory usage
        let currentMemory = getCurrentMemoryUsage()

        // Evict items if over limit
        if currentMemory > maxMemoryBytes || itemCache.count > maxItems {
            await evictLRUItems(targetMemory: maxMemoryBytes * 8 / 10) // Target 80% of max
        }
    }

    private func removeExpiredItems() async {
        let now = Date()
        var expiredIds: [UUID] = []

        for (id, cachedItem) in itemCache {
            if now.timeIntervalSince(cachedItem.cachedAt) > ttlSeconds {
                expiredIds.append(id)
            }
        }

        for id in expiredIds {
            itemCache.removeValue(forKey: id)
            accessOrder.removeAll { $0 == id }
        }
    }

    private func evictLRUItems(targetMemory: Int64) async {
        while getCurrentMemoryUsage() > targetMemory && !accessOrder.isEmpty {
            let lruId = accessOrder.removeFirst()
            itemCache.removeValue(forKey: lruId)
            evictions += 1
        }
    }

    private func getCurrentMemoryUsage() -> Int64 {
        return itemCache.values.reduce(0) { total, cachedItem in
            total + cachedItem.item.metadata.size
        }
    }

    public func getStatistics() async -> CacheStatistics {
        let memoryUsage = getCurrentMemoryUsage()
        let hitRate = hits + misses > 0 ? Double(hits) / Double(hits + misses) : 0

        return CacheStatistics(
            itemCount: itemCache.count,
            collectionCount: collectionCache.count,
            memoryUsageBytes: memoryUsage,
            maxMemoryBytes: maxMemoryBytes,
            hitRate: hitRate,
            totalHits: hits,
            totalMisses: misses,
            totalEvictions: evictions
        )
    }

    public func optimize() async {
        await removeExpiredItems()
        await enforceMemoryLimit()
    }

    public func clear() async {
        itemCache.removeAll()
        collectionCache.removeAll()
        accessOrder.removeAll()
        hits = 0
        misses = 0
        evictions = 0
    }

    // MARK: - Background Cleanup

    private func startCleanupTimer() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000) // 1 minute
                await optimize()
            }
        }
    }

    // MARK: - Preloading

    public func preloadFrequentItems() async {
        // This could be called at startup to preload frequently accessed items
        // Implementation would query the database for most accessed items
        print("Preloading frequent items...")
    }

    public func preloadPinnedItems() async {
        // Preload pinned items since they're likely to be accessed
        print("Preloading pinned items...")
    }
}

// MARK: - Cached Item

private struct CachedItem {
    let item: ClipboardItem
    let cachedAt: Date

    var age: TimeInterval {
        Date().timeIntervalSince(cachedAt)
    }
}

// MARK: - Cache Statistics

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

// MARK: - Cache Configuration

public struct CacheConfiguration {
    public let maxMemoryBytes: Int64
    public let maxItems: Int
    public let ttlSeconds: TimeInterval
    public let preloadPinned: Bool
    public let preloadFrequent: Bool

    public init(
        maxMemoryBytes: Int64 = 50 * 1024 * 1024,
        maxItems: Int = 1000,
        ttlSeconds: TimeInterval = 300,
        preloadPinned: Bool = true,
        preloadFrequent: Bool = false
    ) {
        self.maxMemoryBytes = maxMemoryBytes
        self.maxItems = maxItems
        self.ttlSeconds = ttlSeconds
        self.preloadPinned = preloadPinned
        self.preloadFrequent = preloadFrequent
    }
}