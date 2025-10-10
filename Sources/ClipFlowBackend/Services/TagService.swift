import Foundation
import Combine
import ClipFlowCore

// MARK: - Tag Service

@MainActor
public class TagService {
    public static let shared = TagService()

    // Publishers for reactive updates
    public let tagUpdates = PassthroughSubject<Tag, Never>()
    public let tagDeleted = PassthroughSubject<UUID, Never>()
    public let tagsLoaded = PassthroughSubject<[Tag], Never>()

    private let database = DatabaseManager.shared
    private var cachedTags: [Tag] = []
    private var useRandomColors: Bool = true // Setting for random color assignment

    private init() {
        Task {
            await loadAllTags()
        }
    }

    // MARK: - Tag CRUD Operations

    /// Load all tags from database
    public func loadAllTags() async {
        do {
            let tags = try await database.getTags()
            cachedTags = tags.sorted { $0.createdAt > $1.createdAt }
            tagsLoaded.send(cachedTags)
        } catch {
            NSLog("❌ Failed to load tags: \(error)")
        }
    }

    /// Get all tags (from cache)
    public func getAllTags() -> [Tag] {
        return cachedTags
    }

    /// Create a new tag
    public func createTag(name: String, color: TagColor? = nil) async throws -> Tag {
        let tagColor = color ?? (useRandomColors ? TagColor.random() : .blue)
        let tag = Tag(name: name, color: tagColor)

        try await database.saveTag(tag)
        cachedTags.insert(tag, at: 0)
        tagUpdates.send(tag)

        NSLog("✅ Created tag: \(name) with color: \(tagColor.displayName)")
        return tag
    }

    /// Update an existing tag
    public func updateTag(_ tag: Tag) async throws {
        try await database.updateTag(tag)

        if let index = cachedTags.firstIndex(where: { $0.id == tag.id }) {
            cachedTags[index] = tag
        }

        tagUpdates.send(tag)
        NSLog("✅ Updated tag: \(tag.name)")
    }

    /// Delete a tag
    public func deleteTag(id: UUID) async throws {
        try await database.deleteTag(id: id)

        cachedTags.removeAll { $0.id == id }
        tagDeleted.send(id)

        NSLog("✅ Deleted tag: \(id)")
    }

    /// Get a specific tag by ID
    public func getTag(id: UUID) async throws -> Tag? {
        // Check cache first
        if let cachedTag = cachedTags.first(where: { $0.id == id }) {
            return cachedTag
        }

        // Fallback to database
        return try await database.getTag(id: id)
    }

    // MARK: - Tag-Item Relationships

    /// Add a tag to an item
    public func tagItem(tagId: UUID, itemId: UUID) async throws {
        try await database.addTagToItem(tagId: tagId, itemId: itemId)
        NSLog("✅ Tagged item \(itemId) with tag \(tagId)")
    }

    /// Remove a tag from an item
    public func untagItem(tagId: UUID, itemId: UUID) async throws {
        try await database.removeTagFromItem(tagId: tagId, itemId: itemId)
        NSLog("✅ Removed tag \(tagId) from item \(itemId)")
    }

    /// Get all tags for a specific item
    public func getTagsForItem(itemId: UUID) async throws -> [Tag] {
        return try await database.getTagsForItem(itemId: itemId)
    }

    /// Get all items for a specific tag
    public func getItemsForTag(tagId: UUID) async throws -> [ClipboardItem] {
        return try await database.getItemsForTag(tagId: tagId)
    }

    // MARK: - Batch Operations

    /// Add multiple tags to an item
    public func addTagsToItem(tagIds: [UUID], itemId: UUID) async throws {
        for tagId in tagIds {
            try await database.addTagToItem(tagId: tagId, itemId: itemId)
        }
        NSLog("✅ Added \(tagIds.count) tags to item \(itemId)")
    }

    /// Remove all tags from an item
    public func removeAllTagsFromItem(itemId: UUID) async throws {
        let tags = try await database.getTagsForItem(itemId: itemId)
        for tag in tags {
            try await database.removeTagFromItem(tagId: tag.id, itemId: itemId)
        }
        NSLog("✅ Removed all tags from item \(itemId)")
    }

    // MARK: - Settings

    /// Set whether to use random colors for new tags
    public func setUseRandomColors(_ enabled: Bool) {
        useRandomColors = enabled
        UserDefaults.standard.set(enabled, forKey: "TagService.useRandomColors")
    }

    /// Get current random color setting
    public func getUseRandomColors() -> Bool {
        return useRandomColors
    }

    // MARK: - Utilities

    /// Get tag count for statistics
    public func getTagCount() -> Int {
        return cachedTags.count
    }

    /// Get items count for a specific tag
    public func getItemCountForTag(tagId: UUID) async throws -> Int {
        let items = try await database.getItemsForTag(tagId: tagId)
        return items.count
    }

    /// Check if a tag name already exists
    public func tagExists(name: String) -> Bool {
        return cachedTags.contains { $0.name.lowercased() == name.lowercased() }
    }

    /// Initialize default tags if none exist
    public func initializeDefaultTags() async throws {
        guard cachedTags.isEmpty else { return }

        NSLog("📦 Initializing default tags...")
        for defaultTag in Tag.defaults {
            try await database.saveTag(defaultTag)
            cachedTags.append(defaultTag)
        }

        tagsLoaded.send(cachedTags)
        NSLog("✅ Initialized \(Tag.defaults.count) default tags")
    }
}
