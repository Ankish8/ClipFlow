import Foundation
import ClipFlowCore
import GRDB

// MARK: - Tag Service

@MainActor
public class TagService {
    private let databaseManager: DatabaseManager
    private let cacheManager: CacheManager
    private let performanceMonitor: PerformanceMonitor
    
    public init(
        databaseManager: DatabaseManager = DatabaseManager.shared,
        cacheManager: CacheManager = CacheManager.shared,
        performanceMonitor: PerformanceMonitor = PerformanceMonitor.shared
    ) {
        self.databaseManager = databaseManager
        self.cacheManager = cacheManager
        self.performanceMonitor = performanceMonitor
    }
    
    // MARK: - Tag Management
    
    public func createTag(_ tag: Tag) async throws -> Tag {
        return try await performanceMonitor.measure(operation: "create_tag") {
            var record = TagRecord(from: tag)
            
            try await databaseManager.write { db in
                try record.insert(db)
            }
            
            // Cache the tag
            await cacheManager.cacheTag(tag)
            
            NSLog("✅ Created tag: \(tag.name)")
            return tag
        }
    }
    
    public func getTag(id: UUID) async throws -> Tag? {
        return try await performanceMonitor.measure(operation: "get_tag") {
            // Check cache first
            if let cachedTag = await cacheManager.getTag(id: id) {
                return cachedTag
            }
            
            // Load from database
            guard let record = try await databaseManager.read({ db in
                try TagRecord.fetchOne(db, key: id.uuidString)
            }) else {
                return nil
            }
            
            let tag = try record.toTag()
            
            // Cache for future access
            await cacheManager.cacheTag(tag)
            
            return tag
        }
    }
    
    public func getAllTags() async throws -> [Tag] {
        return try await performanceMonitor.measure(operation: "get_all_tags") {
            let records = try await databaseManager.read { db in
                try TagRecord.fetchAll(db)
            }
            
            let tags = try records.map { try $0.toTag() }
            
            // Cache all tags
            for tag in tags {
                await cacheManager.cacheTag(tag)
            }
            
            NSLog("📋 Retrieved \(tags.count) tags")
            return tags.sorted { $0.name < $1.name }
        }
    }
    
    public func updateTag(_ tag: Tag) async throws {
        try await performanceMonitor.measure(operation: "update_tag") {
            let record = TagRecord(from: tag)
            
            try await databaseManager.write { db in
                try record.update(db)
            }
            
            // Update cache
            await cacheManager.cacheTag(tag)
            
            NSLog("✅ Updated tag: \(tag.name)")
        }
    }
    
    public func deleteTag(id: UUID) async throws {
        try await performanceMonitor.measure(operation: "delete_tag") {
            try await databaseManager.write { db in
                try TagRecord.deleteOne(db, key: id.uuidString)
                
                // Delete all assignments for this tag
                try db.execute(sql: "DELETE FROM tag_assignments WHERE tag_id = ?", arguments: [id.uuidString])
            }
            
            // Remove from cache
            await cacheManager.removeTag(id: id)
            
            NSLog("✅ Deleted tag: \(id)")
        }
    }
    
    // MARK: - Tag Assignment Management
    
    public func assignTag(tagId: UUID, to itemId: UUID) async throws {
        try await performanceMonitor.measure(operation: "assign_tag") {
            let assignment = TagAssignment(tagId: tagId, itemId: itemId)
            var record = TagAssignmentRecord(from: assignment)
            
            try await databaseManager.write { db in
                try record.insert(db)
            }
            
            // Increment tag usage
            if let tag = try await getTag(id: tagId) {
                var updatedTag = tag
                updatedTag.incrementUsage()
                try await updateTag(updatedTag)
            }
            
            NSLog("✅ Assigned tag \(tagId) to item \(itemId)")
        }
    }
    
    public func unassignTag(tagId: UUID, from itemId: UUID) async throws {
        try await performanceMonitor.measure(operation: "unassign_tag") {
            try await databaseManager.write { db in
                try db.execute(sql: """
                    DELETE FROM tag_assignments 
                    WHERE tag_id = ? AND item_id = ?
                """, arguments: [tagId.uuidString, itemId.uuidString])
            }
            
            // Decrement tag usage
            if let tag = try await getTag(id: tagId) {
                var updatedTag = tag
                updatedTag.decrementUsage()
                try await updateTag(updatedTag)
            }
            
            NSLog("✅ Unassigned tag \(tagId) from item \(itemId)")
        }
    }
    
    public func getTagsForItem(itemId: UUID) async throws -> [Tag] {
        return try await performanceMonitor.measure(operation: "get_tags_for_item") {
            let records = try await databaseManager.read { db in
                let sql = """
                    SELECT t.* FROM tags t
                    INNER JOIN tag_assignments ta ON t.id = ta.tag_id
                    WHERE ta.item_id = ?
                    ORDER BY ta.assigned_at DESC
                """
                return try TagRecord.fetchAll(db, sql: sql, arguments: [itemId.uuidString])
            }
            
            return try records.map { try $0.toTag() }
        }
    }
    
    public func getItemsWithTag(tagId: UUID) async throws -> [UUID] {
        return try await performanceMonitor.measure(operation: "get_items_with_tag") {
            let records = try await databaseManager.read { db in
                let sql = """
                    SELECT item_id FROM tag_assignments
                    WHERE tag_id = ?
                    ORDER BY assigned_at DESC
                """
                return try TagAssignmentRecord.fetchAll(db, sql: sql, arguments: [tagId.uuidString])
            }
            
            return records.compactMap { UUID(uuidString: $0.itemId) }
        }
    }
    
    // MARK: - Tag Statistics
    
    public func getTagStatistics() async throws -> TagStatistics {
        return try await performanceMonitor.measure(operation: "get_tag_statistics") {
            let allTags = try await getAllTags()
            
            let totalTags = allTags.count
            let totalAssignments = allTags.reduce(0) { $0 + $1.usageCount }
            let averageUsagePerTag = totalTags > 0 ? Double(totalAssignments) / Double(totalTags) : 0.0
            
            let mostUsedTags = allTags
                .sorted { $0.usageCount > $1.usageCount }
                .prefix(10)
                .map { $0 }
            
            let recentlyUsedTags = allTags
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(10)
                .map { $0 }
            
            let tagsByColor = Dictionary(grouping: allTags, by: { $0.color })
                .mapValues { $0.count }
            
            let usageTrend: [Date: Int] = [:] // TODO: Implement historical tracking
            
            return TagStatistics(
                totalTags: totalTags,
                totalAssignments: totalAssignments,
                averageUsagePerTag: averageUsagePerTag,
                mostUsedTags: Array(mostUsedTags),
                recentlyUsedTags: Array(recentlyUsedTags),
                tagsByColor: tagsByColor,
                usageTrend: usageTrend
            )
        }
    }
    
    public func searchTags(query: String) async throws -> [Tag] {
        return try await performanceMonitor.measure(operation: "search_tags") {
            let allTags = try await getAllTags()
            
            guard !query.isEmpty else { return allTags }
            
            return allTags.filter { tag in
                tag.name.localizedCaseInsensitiveContains(query) ||
                tag.description?.localizedCaseInsensitiveContains(query) == true
            }
        }
    }
    
    // MARK: - Default Tags Setup
    
    public func ensureDefaultTags() async throws {
        let existingTags = try await getAllTags()
        let existingNames = Set(existingTags.map { $0.name })
        
        let defaultTags = Tag.defaultTags
        let missingTags = defaultTags.filter { !existingNames.contains($0.name) }
        
        for tag in missingTags {
            _ = try await createTag(tag)
            NSLog("✅ Created default tag: \(tag.name)")
        }
        
        if !missingTags.isEmpty {
            NSLog("✅ Created \(missingTags.count) default tags")
        }
    }
}

// MARK: - Tag Database Record

struct TagRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var name: String
    var color: String
    var icon: String
    var description: String?
    var usageCount: Int
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval
    
    static let databaseTableName = "tags"
    
    // Custom row decoding
    init(row: Row) throws {
        id = try row["id"]
        name = try row["name"]
        color = try row["color"]
        icon = try row["icon"]
        description = row["description"]
        usageCount = try row["usage_count"]
        createdAt = try row["created_at"]
        modifiedAt = try row["modified_at"]
    }
    
    // Custom persistence
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name
        container["color"] = color
        container["icon"] = icon
        container["description"] = description
        container["usage_count"] = usageCount
        container["created_at"] = createdAt
        container["modified_at"] = modifiedAt
    }
    
    init(from tag: Tag) {
        self.id = tag.id.uuidString
        self.name = tag.name
        self.color = tag.color
        self.icon = tag.icon
        self.description = tag.description
        self.usageCount = tag.usageCount
        self.createdAt = tag.createdAt.timeIntervalSince1970
        self.modifiedAt = tag.modifiedAt.timeIntervalSince1970
    }
    
    func toTag() throws -> Tag {
        guard let uuid = UUID(uuidString: id) else {
            throw DatabaseError.corruptedData("Invalid UUID")
        }
        
        return Tag(
            id: uuid,
            name: name,
            color: color,
            icon: icon,
            description: description,
            usageCount: usageCount,
            createdAt: Date(timeIntervalSince1970: createdAt),
            modifiedAt: Date(timeIntervalSince1970: modifiedAt)
        )
    }
}

// MARK: - Tag Assignment Database Record

struct TagAssignmentRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var tagId: String
    var itemId: String
    var assignedAt: TimeInterval
    var assignedBy: String?
    
    static let databaseTableName = "tag_assignments"
    
    // Custom row decoding
    init(row: Row) throws {
        id = try row["id"]
        tagId = try row["tag_id"]
        itemId = try row["item_id"]
        assignedAt = try row["assigned_at"]
        assignedBy = row["assigned_by"]
    }
    
    // Custom persistence
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["tag_id"] = tagId
        container["item_id"] = itemId
        container["assigned_at"] = assignedAt
        container["assigned_by"] = assignedBy
    }
    
    init(from assignment: TagAssignment) {
        self.id = assignment.id.uuidString
        self.tagId = assignment.tagId.uuidString
        self.itemId = assignment.itemId.uuidString
        self.assignedAt = assignment.assignedAt.timeIntervalSince1970
        self.assignedBy = assignment.assignedBy
    }
    
    func toTagAssignment() throws -> TagAssignment {
        guard let id = UUID(uuidString: id),
              let tagId = UUID(uuidString: tagId),
              let itemId = UUID(uuidString: itemId) else {
            throw DatabaseError.corruptedData("Invalid UUID")
        }
        
        return TagAssignment(
            id: id,
            tagId: tagId,
            itemId: itemId,
            assignedAt: Date(timeIntervalSince1970: assignedAt),
            assignedBy: assignedBy
        )
    }
}