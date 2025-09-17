import Foundation
import Combine
import ClipFlowCore

// MARK: - Tag Service Protocol

@MainActor
public protocol TagServiceAPI {
    // MARK: - Tag CRUD Operations
    
    /// Create a new tag
    func createTag(name: String, color: String, icon: String?, description: String?) async throws -> Tag
    
    /// Get all tags
    func getAllTags() async throws -> [Tag]
    
    /// Get tag by ID
    func getTag(id: UUID) async throws -> Tag?
    
    /// Update tag metadata
    func updateTag(id: UUID, name: String?, color: String?, icon: String?, description: String?) async throws -> Tag
    
    /// Delete a tag
    func deleteTag(id: UUID) async throws
    
    // MARK: - Tag Assignment Operations
    
    /// Add tags to a clipboard item
    func addTags(_ tags: Set<String>, to itemId: UUID) async throws
    
    /// Remove tags from a clipboard item
    func removeTags(_ tags: Set<String>, from itemId: UUID) async throws
    
    /// Set tags for a clipboard item (replaces all existing tags)
    func setTags(_ tags: Set<String>, for itemId: UUID) async throws
    
    /// Get all tags for a specific item
    func getTags(for itemId: UUID) async throws -> Set<String>
    
    /// Get all items with a specific tag
    func getItems(with tag: String) async throws -> [ClipboardItem]
    
    /// Get all items with any of the specified tags
    func getItems(withAny tags: Set<String>) async throws -> [ClipboardItem]
    
    /// Get all items with all of the specified tags
    func getItems(withAll tags: Set<String>) async throws -> [ClipboardItem]
    
    // MARK: - Tag Search and Filtering
    
    /// Search tags by name
    func searchTags(query: String) async throws -> [Tag]
    
    /// Get tags by usage count (most used first)
    func getTagsByUsage(limit: Int?) async throws -> [Tag]
    
    /// Get recently created tags
    func getRecentTags(limit: Int?) async throws -> [Tag]
    
    /// Get tag statistics
    func getTagStatistics() async throws -> TagStatistics
    
    // MARK: - Publishers
    
    var tagUpdates: AnyPublisher<TagUpdate, Never> { get }
    var errors: AnyPublisher<TagError, Never> { get }
}

// MARK: - Tag Update Types

public enum TagUpdate {
    case tagCreated(Tag)
    case tagUpdated(Tag)
    case tagDeleted(UUID)
    case tagsAdded(Set<String>, to: UUID)
    case tagsRemoved(Set<String>, from: UUID)
    case tagsSet(Set<String>, for: UUID)
}

public enum TagError: Error {
    case tagNotFound(UUID)
    case tagAlreadyExists(String)
    case invalidTagName(String)
    case invalidTagColor(String)
    case itemNotFound(UUID)
    case storageFailed(Error)
    case permissionDenied
}

// MARK: - Tag Service Implementation

@MainActor
public class TagService: TagServiceAPI {
    
    // MARK: - Properties
    
    private let storageService: StorageService
    private let tagUpdatesPublisher = PassthroughSubject<TagUpdate, Never>()
    private let errorsPublisher = PassthroughSubject<TagError, Never>()
    
    // In-memory cache for tags (temporary until database is fixed)
    private var tagsCache: [UUID: Tag] = [:]
    private var itemTagsCache: [UUID: Set<String>] = [:]
    
    // MARK: - Publishers
    
    public var tagUpdates: AnyPublisher<TagUpdate, Never> {
        tagUpdatesPublisher.eraseToAnyPublisher()
    }
    
    public var errors: AnyPublisher<TagError, Never> {
        errorsPublisher.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    public init(storageService: StorageService) {
        self.storageService = storageService
        initializeDefaultTags()
    }
    
    // MARK: - Private Methods
    
    private func initializeDefaultTags() {
        let defaultTags = Tag.defaultTags
        for tag in defaultTags {
            tagsCache[tag.id] = tag
        }
    }
    
    private func validateTagName(_ name: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TagError.invalidTagName("Tag name cannot be empty")
        }
        guard trimmedName.count <= 50 else {
            throw TagError.invalidTagName("Tag name cannot exceed 50 characters")
        }
        
        // Check for duplicate names
        let existingNames = tagsCache.values.map { $0.name.lowercased() }
        if existingNames.contains(trimmedName.lowercased()) {
            throw TagError.tagAlreadyExists(trimmedName)
        }
    }
    
    private func validateTagColor(_ color: String) throws {
        guard color.hasPrefix("#") else {
            throw TagError.invalidTagColor("Color must start with #")
        }
        guard color.count == 7 else {
            throw TagError.invalidTagColor("Color must be in #RRGGBB format")
        }
        
        let hexValue = String(color.dropFirst())
        guard Int(hexValue, radix: 16) != nil else {
            throw TagError.invalidTagColor("Invalid hex color value")
        }
    }
    
    // MARK: - Tag CRUD Operations
    
    public func createTag(name: String, color: String, icon: String?, description: String?) async throws -> Tag {
        try validateTagName(name)
        try validateTagColor(color)
        
        let tag = Tag(
            name: name,
            color: color,
            icon: icon,
            description: description
        )
        
        tagsCache[tag.id] = tag
        tagUpdatesPublisher.send(.tagCreated(tag))
        
        return tag
    }
    
    public func getAllTags() async throws -> [Tag] {
        return Array(tagsCache.values)
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    public func getTag(id: UUID) async throws -> Tag? {
        return tagsCache[id]
    }
    
    public func updateTag(id: UUID, name: String?, color: String?, icon: String?, description: String?) async throws -> Tag {
        guard var tag = tagsCache[id] else {
            throw TagError.tagNotFound(id)
        }
        
        if let newName = name {
            try validateTagName(newName)
        }
        
        if let newColor = color {
            try validateTagColor(newColor)
        }
        
        tag.updateMetadata(name: name, color: color, icon: icon, description: description)
        tagsCache[id] = tag
        tagUpdatesPublisher.send(.tagUpdated(tag))
        
        return tag
    }
    
    public func deleteTag(id: UUID) async throws {
        guard tagsCache[id] != nil else {
            throw TagError.tagNotFound(id)
        }
        
        // Remove tag from all items
        let tagName = tagsCache[id]?.name ?? ""
        for (itemId, tags) in itemTagsCache {
            if tags.contains(tagName) {
                var updatedTags = tags
                updatedTags.remove(tagName)
                itemTagsCache[itemId] = updatedTags
            }
        }
        
        tagsCache.removeValue(forKey: id)
        tagUpdatesPublisher.send(.tagDeleted(id))
    }
    
    // MARK: - Tag Assignment Operations
    
    public func addTags(_ tags: Set<String>, to itemId: UUID) async throws {
        var currentTags = itemTagsCache[itemId] ?? []
        let newTags = tags.subtracting(currentTags)
        
        if !newTags.isEmpty {
            currentTags.formUnion(newTags)
            itemTagsCache[itemId] = currentTags
            tagUpdatesPublisher.send(.tagsAdded(newTags, to: itemId))
        }
    }
    
    public func removeTags(_ tags: Set<String>, from itemId: UUID) async throws {
        var currentTags = itemTagsCache[itemId] ?? []
        let removedTags = tags.intersection(currentTags)
        
        if !removedTags.isEmpty {
            currentTags.subtract(removedTags)
            itemTagsCache[itemId] = currentTags
            tagUpdatesPublisher.send(.tagsRemoved(removedTags, from: itemId))
        }
    }
    
    public func setTags(_ tags: Set<String>, for itemId: UUID) async throws {
        let oldTags = itemTagsCache[itemId] ?? []
        let addedTags = tags.subtracting(oldTags)
        let removedTags = oldTags.subtracting(tags)
        
        itemTagsCache[itemId] = tags
        
        if !addedTags.isEmpty || !removedTags.isEmpty {
            tagUpdatesPublisher.send(.tagsSet(tags, for: itemId))
        }
    }
    
    public func getTags(for itemId: UUID) async throws -> Set<String> {
        return itemTagsCache[itemId] ?? []
    }
    
    public func getItems(with tag: String) async throws -> [ClipboardItem] {
        // This would normally query the storage service
        // For now, return empty array as we don't have direct access to items
        return []
    }
    
    public func getItems(withAny tags: Set<String>) async throws -> [ClipboardItem] {
        // This would normally query the storage service
        return []
    }
    
    public func getItems(withAll tags: Set<String>) async throws -> [ClipboardItem] {
        // This would normally query the storage service
        return []
    }
    
    // MARK: - Tag Search and Filtering
    
    public func searchTags(query: String) async throws -> [Tag] {
        let lowercasedQuery = query.lowercased()
        return tagsCache.values
            .filter { tag in
                tag.name.lowercased().contains(lowercasedQuery) ||
                tag.description?.lowercased().contains(lowercasedQuery) == true
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    public func getTagsByUsage(limit: Int?) async throws -> [Tag] {
        let sortedTags = tagsCache.values
            .sorted { $0.usageCount > $1.usageCount }
        
        if let limit = limit {
            return Array(sortedTags.prefix(limit))
        }
        return Array(sortedTags)
    }
    
    public func getRecentTags(limit: Int?) async throws -> [Tag] {
        let sortedTags = tagsCache.values
            .sorted { $0.modifiedAt > $1.modifiedAt }
        
        if let limit = limit {
            return Array(sortedTags.prefix(limit))
        }
        return Array(sortedTags)
    }
    
    public func getTagStatistics() async throws -> TagStatistics {
        let totalTags = tagsCache.count
        let totalTaggedItems = Set(itemTagsCache.values.flatMap { $0 }).count
        
        let mostUsedTags = try await getTagsByUsage(limit: 5)
        let recentlyCreatedTags = try await getRecentTags(limit: 5)
        
        let tagsByColor = Dictionary(grouping: tagsCache.values, by: { $0.color })
            .mapValues { $0.count }
        
        return TagStatistics(
            totalTags: totalTags,
            totalTaggedItems: totalTaggedItems,
            mostUsedTags: mostUsedTags,
            recentlyCreatedTags: recentlyCreatedTags,
            tagsByColor: tagsByColor
        )
    }
}