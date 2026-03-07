import Foundation
import GRDB
import ClipFlowCore

// MARK: - Database Manager

@MainActor
public class DatabaseManager {
    private let dbQueue: DatabaseQueue
    private let migrator: DatabaseMigrator

    public static let shared = DatabaseManager()

    private init() {
        do {
            let dbPath = try Self.databasePath()
            self.dbQueue = try DatabaseQueue(path: dbPath)
            self.migrator = Self.createMigrator()
            try migrator.migrate(dbQueue)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    // MARK: - Database Path

    private static func databasePath() throws -> String {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appFolder = appSupport.appendingPathComponent("ClipFlow", isDirectory: true)
        try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        return appFolder.appendingPathComponent("ClipFlow.sqlite").path
    }

    // MARK: - Migrations

    private static func createMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1.0") { db in
            // Main clipboard items table
            try db.create(table: "clipboard_items") { t in
                t.primaryKey("id", .text)
                t.column("content_type", .text).notNull()
                t.column("content_data", .blob)
                t.column("content_text", .text) // For FTS
                t.column("metadata", .text).notNull() // JSON
                t.column("source", .text).notNull() // JSON
                t.column("timestamps", .text).notNull() // JSON
                t.column("security", .text).notNull() // JSON
                t.column("collection_ids", .text) // JSON array
                t.column("is_favorite", .boolean).defaults(to: false)
                t.column("is_pinned", .boolean).defaults(to: false)
                t.column("is_deleted", .boolean).defaults(to: false)
                t.column("created_at", .integer).notNull()
                t.column("modified_at", .integer)
                t.column("accessed_at", .integer)
                t.column("expires_at", .integer)
                t.column("hash", .text).notNull()
            }

            // Collections table
            try db.create(table: "collections") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("icon", .text).notNull()
                t.column("color", .text).notNull()
                t.column("is_shared", .boolean).defaults(to: false)
                t.column("share_settings", .text) // JSON
                t.column("created_at", .integer).notNull()
                t.column("modified_at", .integer).notNull()
            }

            // Collection items junction table
            try db.create(table: "collection_items") { t in
                t.column("collection_id", .text).notNull()
                    .references("collections", onDelete: .cascade)
                t.column("item_id", .text).notNull()
                    .references("clipboard_items", onDelete: .cascade)
                t.column("added_at", .integer).notNull()
                t.primaryKey(["collection_id", "item_id"])
            }

            // Snippets table
            try db.create(table: "snippets") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("placeholders", .text) // JSON
                t.column("keyword", .text).unique()
                t.column("category", .text).notNull()
                t.column("usage_count", .integer).defaults(to: 0)
                t.column("created_at", .integer).notNull()
                t.column("modified_at", .integer).notNull()
            }

            // Automation rules table
            try db.create(table: "automation_rules") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("trigger_data", .text).notNull() // JSON
                t.column("conditions", .text) // JSON
                t.column("actions", .text).notNull() // JSON
                t.column("is_enabled", .boolean).defaults(to: true)
                t.column("execution_count", .integer).defaults(to: 0)
                t.column("last_executed", .integer)
                t.column("created_at", .integer).notNull()
                t.column("modified_at", .integer).notNull()
            }

            // Full-text search table
            try db.create(virtualTable: "items_fts", using: FTS5()) { t in
                t.column("content_text")
                t.column("application_name")
                t.tokenizer = .porter()
            }

            // Performance indexes
            try db.create(index: "idx_items_created", on: "clipboard_items", columns: ["created_at"])
            try db.create(index: "idx_items_pinned", on: "clipboard_items", columns: ["is_pinned", "created_at"])
            try db.create(index: "idx_items_favorite", on: "clipboard_items", columns: ["is_favorite", "created_at"])
            try db.create(index: "idx_items_deleted", on: "clipboard_items", columns: ["is_deleted"])
            try db.create(index: "idx_items_hash", on: "clipboard_items", columns: ["hash"])
            try db.create(index: "idx_items_expires", on: "clipboard_items", columns: ["expires_at"])
            try db.create(index: "idx_collections_shared", on: "collections", columns: ["is_shared"])
            try db.create(index: "idx_snippets_keyword", on: "snippets", columns: ["keyword"])
            try db.create(index: "idx_snippets_category", on: "snippets", columns: ["category"])
            try db.create(index: "idx_rules_enabled", on: "automation_rules", columns: ["is_enabled"])
        }

        migrator.registerMigration("v1.1") { db in
            // Add search optimization
            try db.create(index: "idx_items_content_type", on: "clipboard_items", columns: ["content_type"])
            try db.create(index: "idx_items_size", on: "clipboard_items", columns: ["metadata"])

            // Add performance table for monitoring
            try db.create(table: "performance_metrics") { t in
                t.primaryKey("id", .text)
                t.column("operation", .text).notNull()
                t.column("duration_ms", .integer).notNull()
                t.column("memory_usage", .integer)
                t.column("timestamp", .integer).notNull()
                t.column("metadata", .text) // JSON
            }
        }

        migrator.registerMigration("v1.2") { db in
            // Tags table
            try db.create(table: "tags") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().unique()
                t.column("color", .text).notNull()
                t.column("icon", .text).notNull().defaults(to: "tag")
                t.column("description", .text)
                t.column("usage_count", .integer).defaults(to: 0)
                t.column("created_at", .integer).notNull()
                t.column("modified_at", .integer).notNull()
            }

            // Item-Tags junction table (many-to-many)
            try db.create(table: "item_tags") { t in
                t.column("item_id", .text).notNull()
                    .references("clipboard_items", onDelete: .cascade)
                t.column("tag_id", .text).notNull()
                    .references("tags", onDelete: .cascade)
                t.column("added_at", .integer).notNull()
                t.primaryKey(["item_id", "tag_id"])
            }

            // Add tag_ids column to clipboard_items for denormalized access
            try db.alter(table: "clipboard_items") { t in
                t.add(column: "tag_ids", .text)
            }

            // Performance indexes for tags
            try db.create(index: "idx_tags_name", on: "tags", columns: ["name"])
            try db.create(index: "idx_tags_usage", on: "tags", columns: ["usage_count"])
            try db.create(index: "idx_item_tags_item", on: "item_tags", columns: ["item_id"])
            try db.create(index: "idx_item_tags_tag", on: "item_tags", columns: ["tag_id"])
        }

        migrator.registerMigration("v1.3") { db in
            let hasTagIconColumn = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pragma_table_info('tags') WHERE name = 'icon'"
            ) ?? 0) > 0
            if !hasTagIconColumn {
                try db.alter(table: "tags") { t in
                    t.add(column: "icon", .text).notNull().defaults(to: "tag")
                }
            }

            let hasTagDescriptionColumn = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pragma_table_info('tags') WHERE name = 'description'"
            ) ?? 0) > 0
            if !hasTagDescriptionColumn {
                try db.alter(table: "tags") { t in
                    t.add(column: "description", .text)
                }
            }

            let hasTagUsageColumn = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pragma_table_info('tags') WHERE name = 'usage_count'"
            ) ?? 0) > 0
            if !hasTagUsageColumn {
                try db.alter(table: "tags") { t in
                    t.add(column: "usage_count", .integer).defaults(to: 0)
                }
            }

            let hasTagIdsColumn = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'tag_ids'"
            ) ?? 0) > 0

            if !hasTagIdsColumn {
                try db.alter(table: "clipboard_items") { t in
                    t.add(column: "tag_ids", .text)
                }
            }

            let hasItemTagsTable = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'item_tags'"
            ) ?? 0) > 0

            if !hasItemTagsTable {
                try db.create(table: "item_tags") { t in
                    t.column("item_id", .text).notNull()
                        .references("clipboard_items", onDelete: .cascade)
                    t.column("tag_id", .text).notNull()
                        .references("tags", onDelete: .cascade)
                    t.column("added_at", .integer).notNull()
                    t.primaryKey(["item_id", "tag_id"])
                }
            }

            let hasItemIndex = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_item_tags_item'"
            ) ?? 0) > 0
            if !hasItemIndex {
                try db.create(index: "idx_item_tags_item", on: "item_tags", columns: ["item_id"])
            }

            let hasTagIndex = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_item_tags_tag'"
            ) ?? 0) > 0
            if !hasTagIndex {
                try db.create(index: "idx_item_tags_tag", on: "item_tags", columns: ["tag_id"])
            }

            let hasTagUsageIndex = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_tags_usage'"
            ) ?? 0) > 0
            if !hasTagUsageIndex {
                try db.create(index: "idx_tags_usage", on: "tags", columns: ["usage_count"])
            }

            func encodedTagIds(_ tagIds: Set<UUID>) -> String? {
                guard !tagIds.isEmpty else { return nil }
                return try? JSONEncoder().encode(Array(tagIds)).base64EncodedString()
            }

            func writeTagIds(_ tagIds: Set<UUID>, for itemIdString: String) throws {
                if let encodedTagIds = encodedTagIds(tagIds) {
                    try db.execute(
                        sql: "UPDATE clipboard_items SET tag_ids = ? WHERE id = ?",
                        arguments: [encodedTagIds, itemIdString]
                    )
                } else {
                    try db.execute(
                        sql: "UPDATE clipboard_items SET tag_ids = NULL WHERE id = ?",
                        arguments: [itemIdString]
                    )
                }
            }

            // Repair installs that already had item_tags but never got the denormalized
            // clipboard_items.tag_ids column populated.
            let itemIdsWithJunctionTags = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT item_id FROM item_tags"
            )
            for itemIdString in itemIdsWithJunctionTags {
                let tagIdStrings = try String.fetchAll(
                    db,
                    sql: "SELECT tag_id FROM item_tags WHERE item_id = ?",
                    arguments: [itemIdString]
                )
                let tagIds = Set(tagIdStrings.compactMap(UUID.init(uuidString:)))
                try writeTagIds(tagIds, for: itemIdString)
            }

            // Repair installs that stored tag_ids on clipboard_items but never created
            // the item_tags junction table.
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, tag_ids FROM clipboard_items WHERE tag_ids IS NOT NULL"
            )
            let decoder = JSONDecoder()
            for row in rows {
                let itemIdString: String = row["id"]
                guard let tagIdsString: String = row["tag_ids"],
                      let tagIdsData = Data(base64Encoded: tagIdsString),
                      let decodedTagIds = try? decoder.decode([UUID].self, from: tagIdsData) else {
                    continue
                }

                for tagId in Set(decodedTagIds) {
                    try db.execute(
                        sql: """
                            INSERT OR IGNORE INTO item_tags (item_id, tag_id, added_at)
                            VALUES (?, ?, ?)
                        """,
                        arguments: [itemIdString, tagId.uuidString, Date().timeIntervalSince1970]
                    )
                }
            }
        }

        return migrator
    }

    // MARK: - Database Operations

    public func write<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try dbQueue.write(block)
    }

    public func read<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try dbQueue.read(block)
    }

    // MARK: - Clipboard Items

    public func saveItem(_ item: ClipboardItem) async throws {
        NSLog("🗄️ DatabaseManager.saveItem started")

        try await write { db in
            let record = ClipboardItemRecord(from: item)
            
            // Use INSERT OR REPLACE to handle duplicates gracefully
            try db.execute(sql: """
                INSERT OR REPLACE INTO clipboard_items (
                    id, content_type, content_data, content_text, metadata, source,
                    timestamps, security, collection_ids, tag_ids, is_favorite, is_pinned,
                    is_deleted, created_at, modified_at, accessed_at, expires_at, hash
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                record.id,
                record.contentType,
                record.contentData,
                record.contentText,
                record.metadata,
                record.source,
                record.timestamps,
                record.security,
                record.collectionIds,
                record.tagIds,
                record.isFavorite,
                record.isPinned,
                record.isDeleted,
                record.createdAt,
                record.modifiedAt as DatabaseValueConvertible?,
                record.accessedAt as DatabaseValueConvertible?,
                record.expiresAt as DatabaseValueConvertible?,
                record.hash
            ])

            // Update FTS index for search functionality (only if content_text exists)
            if let contentText = record.contentText, !contentText.isEmpty {
                do {
                    try db.execute(sql: """
                        INSERT OR REPLACE INTO items_fts (rowid, content_text, application_name)
                        VALUES (
                            (SELECT rowid FROM clipboard_items WHERE id = ?),
                            ?,
                            ?
                        )
                    """, arguments: [
                        record.id,
                        contentText,
                        item.source.applicationName ?? ""
                    ])
                } catch {
                    NSLog("⚠️ Failed to update FTS index: \(error)")
                }
            }
            
            NSLog("✅ Successfully saved item \(item.id) to database")
        }
        
        NSLog("✅ DatabaseManager.saveItem completed successfully")
    }

    public func updateItem(_ item: ClipboardItem) async throws {
        try await write { db in
            let record = ClipboardItemRecord(from: item)
            try record.update(db)

            // Update FTS index
            try db.execute(sql: """
                UPDATE items_fts SET
                    content_text = ?,
                    application_name = ?
                WHERE rowid = (SELECT rowid FROM clipboard_items WHERE id = ?)
            """, arguments: [
                item.content.displayText,
                item.source.applicationName ?? "",
                item.id.uuidString
            ])
        }
    }

    public func getItem(id: UUID) async throws -> ClipboardItem? {
        try await read { db in
            if let record = try ClipboardItemRecord.fetchOne(db, key: id.uuidString) {
                return try record.toClipboardItem()
            }
            return nil
        }
    }

    public func getItem(hash: String) async throws -> ClipboardItem? {
        try await read { db in
            guard let record = try ClipboardItemRecord.fetchOne(
                db,
                sql: """
                    SELECT * FROM clipboard_items
                    WHERE hash = ? AND is_deleted = 0
                    ORDER BY created_at DESC
                    LIMIT 1
                """,
                arguments: [hash]
            ) else {
                return nil
            }

            return try record.toClipboardItem()
        }
    }

    public func getItems(
        limit: Int = 100,
        offset: Int = 0,
        filter: ItemFilter? = nil
    ) async throws -> [ClipboardItem] {
        return try await read { db in
            var sql = "SELECT * FROM clipboard_items WHERE is_deleted = 0"
            var arguments: [DatabaseValueConvertible] = []

            if let filter = filter {
                let (filterSQL, filterArgs) = filter.buildSQL()
                sql += " AND " + filterSQL
                arguments.append(contentsOf: filterArgs)
            }

            sql += " ORDER BY "
            sql += (filter?.sortBy == .lastAccessed) ? "accessed_at DESC" : "created_at DESC"
            sql += " LIMIT ? OFFSET ?"

            arguments.append(limit)
            arguments.append(offset)

            NSLog("🔍 Executing query: \(sql) with arguments: \(arguments)")
            
            do {
                let records = try ClipboardItemRecord.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
                var items: [ClipboardItem] = []
                
                for record in records {
                    do {
                        let item = try record.toClipboardItem()
                        items.append(item)
                    } catch {
                        NSLog("⚠️ Failed to decode record \(record.id): \(error)")
                        // Skip this record but continue with others
                    }
                }
                
                NSLog("📋 Retrieved \(items.count) valid items from database (out of \(records.count) records)")
                return items
            } catch {
                NSLog("❌ Failed to fetch items from database: \(error)")
                return [] // Return empty array on error
            }
        }
    }

    public func searchItems(query: String, limit: Int = 50) async throws -> [ClipboardItem] {
        return try await read { db in
            // Use a simpler search that joins with FTS if available, falls back to LIKE
            let sql = """
                SELECT ci.* FROM clipboard_items ci
                WHERE ci.is_deleted = 0 AND (
                    ci.content_text LIKE ? OR
                    ci.id IN (
                        SELECT rowid FROM items_fts 
                        WHERE items_fts MATCH ?
                    )
                )
                ORDER BY ci.created_at DESC
                LIMIT ?
            """
            
            let searchTerm = "%\(query)%"
            let records = try ClipboardItemRecord.fetchAll(db, sql: sql, arguments: [searchTerm, query, limit])
            let items = try records.map { try $0.toClipboardItem() }
            
            NSLog("🔍 Search for '\(query)' returned \(items.count) items")
            return items
        }
    }

    public func deleteItems(ids: [UUID], permanent: Bool = false) async throws {
        try await write { db in
            if permanent {
                for id in ids {
                    try db.execute(sql: "DELETE FROM clipboard_items WHERE id = ?", arguments: [id.uuidString])
                }
            } else {
                for id in ids {
                    try db.execute(sql: "UPDATE clipboard_items SET is_deleted = 1, modified_at = ? WHERE id = ?",
                                  arguments: [Date().timeIntervalSince1970, id.uuidString])
                }
            }
        }
    }

    // MARK: - Collections

    public func saveCollection(_ collection: Collection) async throws {
        try await write { db in
            var record = CollectionRecord(from: collection)
            try record.insert(db)

            // Add collection items
            for itemId in collection.itemIds {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO collection_items (collection_id, item_id, added_at)
                    VALUES (?, ?, ?)
                """, arguments: [collection.id.uuidString, itemId.uuidString, Date().timeIntervalSince1970])
            }
        }
    }

    public func getCollections() async throws -> [Collection] {
        try await read { db in
            let records = try CollectionRecord.fetchAll(db)
            var collections: [Collection] = []

            for record in records {
                let itemIdStrings = try String.fetchAll(db, sql: """
                    SELECT item_id FROM collection_items WHERE collection_id = ?
                """, arguments: [record.id])
                let itemIds = Set(itemIdStrings.compactMap { UUID(uuidString: $0) })

                var collection = try record.toCollection()
                collection.itemIds = itemIds
                collections.append(collection)
            }

            return collections
        }
    }

    // MARK: - Performance Monitoring

    public func logPerformanceMetric(operation: String, duration: TimeInterval, memoryUsage: Int64?) async {
        do {
            try await write { db in
                try db.execute(sql: """
                    INSERT INTO performance_metrics (id, operation, duration_ms, memory_usage, timestamp, metadata)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [
                    UUID().uuidString,
                    operation,
                    Int(duration * 1000), // Convert to milliseconds
                    memoryUsage,
                    Int(Date().timeIntervalSince1970),
                    "{}" // Empty JSON for now
                ])
            }
        } catch {
            print("Failed to log performance metric: \(error)")
        }
    }

    // MARK: - Cleanup

    public func cleanupExpiredItems() async throws {
        try await write { db in
            let now = Date().timeIntervalSince1970
            try db.execute(sql: """
                UPDATE clipboard_items
                SET is_deleted = 1, modified_at = ?
                WHERE expires_at IS NOT NULL AND expires_at < ? AND is_deleted = 0
            """, arguments: [now, now])
        }
    }

    public func vacuumDatabase() async throws {
        try await write { db in
            try db.execute(sql: "VACUUM")
        }
    }

    // MARK: - Tags

    public func saveTag(_ tag: Tag) async throws {
        try await write { db in
            var record = TagRecord(from: tag)
            try record.insert(db)
        }
    }

    public func updateTag(_ tag: Tag) async throws {
        NSLog("📝 DatabaseManager: Updating tag \(tag.id) - '\(tag.name)'")
        try await write { db in
            // Use raw SQL update to avoid GRDB record issues
            try db.execute(sql: """
                UPDATE tags
                SET name = ?, color = ?, modified_at = ?
                WHERE id = ?
            """, arguments: [
                tag.name,
                tag.color.rawValue,
                tag.modifiedAt.timeIntervalSince1970,
                tag.id.uuidString
            ])

            NSLog("✅ DatabaseManager: Successfully updated tag '\(tag.name)' in database")
        }
    }

    public func deleteTag(id: UUID) async throws {
        try await write { db in
            let tagIdString = id.uuidString

            // Check if item_tags table exists (older installs may not have repaired yet)
            let tableExists = try Bool.fetchOne(db, sql: """
                SELECT COUNT(*) > 0 FROM sqlite_master
                WHERE type='table' AND name='item_tags'
            """) ?? false
            let hasTagIdsColumn = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'tag_ids'"
            ) ?? 0) > 0

            if tableExists {
                // Get all items with this tag
                let itemIds = try String.fetchAll(db, sql: """
                    SELECT item_id FROM item_tags WHERE tag_id = ?
                """, arguments: [tagIdString])

                // Delete the tag (will cascade to item_tags)
                try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [tagIdString])

                // Update denormalized tag_ids for affected items
                for itemId in itemIds {
                    if let item = try ClipboardItemRecord.fetchOne(db, key: itemId) {
                        var clipboardItem = try item.toClipboardItem()
                        clipboardItem.tagIds.remove(id)
                        if hasTagIdsColumn {
                            let encodedTagIds = clipboardItem.tagIds.isEmpty
                                ? nil
                                : (try? JSONEncoder().encode(Array(clipboardItem.tagIds)).base64EncodedString())
                            if let encodedTagIds {
                                try db.execute(
                                    sql: "UPDATE clipboard_items SET tag_ids = ?, modified_at = ? WHERE id = ?",
                                    arguments: [encodedTagIds, Date().timeIntervalSince1970, itemId]
                                )
                            } else {
                                try db.execute(
                                    sql: "UPDATE clipboard_items SET tag_ids = NULL, modified_at = ? WHERE id = ?",
                                    arguments: [Date().timeIntervalSince1970, itemId]
                                )
                            }
                        }
                    }
                }
            } else {
                // Table doesn't exist yet, just delete the tag
                NSLog("⚠️ item_tags table doesn't exist, deleting tag without junction table cleanup")
                try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [tagIdString])
            }

            NSLog("✅ DatabaseManager: Successfully deleted tag \(tagIdString)")
        }
    }

    public func getTags() async throws -> [Tag] {
        try await read { db in
            let records = try TagRecord.fetchAll(db)
            return try records.map { try $0.toTag() }
        }
    }

    public func getTag(id: UUID) async throws -> Tag? {
        try await read { db in
            if let record = try TagRecord.fetchOne(db, key: id.uuidString) {
                return try record.toTag()
            }
            return nil
        }
    }

    // MARK: - Tag-Item Relationships

    public func addTagToItem(tagId: UUID, itemId: UUID) async throws {
        try await write { db in
            let hasItemTagsTable = try Bool.fetchOne(db, sql: """
                SELECT COUNT(*) > 0 FROM sqlite_master
                WHERE type='table' AND name='item_tags'
            """) ?? false
            let hasTagIdsColumn = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'tag_ids'"
            ) ?? 0) > 0

            if hasItemTagsTable {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO item_tags (item_id, tag_id, added_at)
                    VALUES (?, ?, ?)
                """, arguments: [itemId.uuidString, tagId.uuidString, Date().timeIntervalSince1970])
            }

            // Update denormalized tag_ids in clipboard_items
            if hasTagIdsColumn,
               let item = try ClipboardItemRecord.fetchOne(db, key: itemId.uuidString) {
                var clipboardItem = try item.toClipboardItem()
                clipboardItem.tagIds.insert(tagId)
                let encodedTagIds = try JSONEncoder().encode(Array(clipboardItem.tagIds)).base64EncodedString()
                try db.execute(
                    sql: "UPDATE clipboard_items SET tag_ids = ?, modified_at = ? WHERE id = ?",
                    arguments: [encodedTagIds, Date().timeIntervalSince1970, itemId.uuidString]
                )
            }
        }
    }

    public func removeTagFromItem(tagId: UUID, itemId: UUID) async throws {
        try await write { db in
            let hasItemTagsTable = try Bool.fetchOne(db, sql: """
                SELECT COUNT(*) > 0 FROM sqlite_master
                WHERE type='table' AND name='item_tags'
            """) ?? false
            let hasTagIdsColumn = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'tag_ids'"
            ) ?? 0) > 0

            if hasItemTagsTable {
                try db.execute(sql: """
                    DELETE FROM item_tags WHERE item_id = ? AND tag_id = ?
                """, arguments: [itemId.uuidString, tagId.uuidString])
            }

            // Update denormalized tag_ids in clipboard_items
            if hasTagIdsColumn,
               let item = try ClipboardItemRecord.fetchOne(db, key: itemId.uuidString) {
                var clipboardItem = try item.toClipboardItem()
                clipboardItem.tagIds.remove(tagId)
                let modifiedAt = Date().timeIntervalSince1970
                if clipboardItem.tagIds.isEmpty {
                    try db.execute(
                        sql: "UPDATE clipboard_items SET tag_ids = NULL, modified_at = ? WHERE id = ?",
                        arguments: [modifiedAt, itemId.uuidString]
                    )
                } else {
                    let encodedTagIds = try JSONEncoder().encode(Array(clipboardItem.tagIds)).base64EncodedString()
                    try db.execute(
                        sql: "UPDATE clipboard_items SET tag_ids = ?, modified_at = ? WHERE id = ?",
                        arguments: [encodedTagIds, modifiedAt, itemId.uuidString]
                    )
                }
            }
        }
    }

    public func getTagsForItem(itemId: UUID) async throws -> [Tag] {
        try await read { db in
            let tagIds = try String.fetchAll(db, sql: """
                SELECT tag_id FROM item_tags WHERE item_id = ?
            """, arguments: [itemId.uuidString])

            var tags: [Tag] = []
            for tagIdString in tagIds {
                if let record = try TagRecord.fetchOne(db, key: tagIdString) {
                    tags.append(try record.toTag())
                }
            }
            return tags
        }
    }

    public func getItemsForTag(tagId: UUID) async throws -> [ClipboardItem] {
        try await read { db in
            let itemIds = try String.fetchAll(db, sql: """
                SELECT item_id FROM item_tags WHERE tag_id = ?
            """, arguments: [tagId.uuidString])

            var items: [ClipboardItem] = []
            for itemIdString in itemIds {
                if let record = try ClipboardItemRecord.fetchOne(db, key: itemIdString) {
                    items.append(try record.toClipboardItem())
                }
            }
            return items
        }
    }
}

// MARK: - Item Filter

public struct ItemFilter {
    let contentTypes: [String]?
    let applications: [String]?
    let dateRange: ClosedRange<Date>?
    let isFavorite: Bool?
    let isPinned: Bool?
    let sortBy: SortOption

    public enum SortOption {
        case createdAt, lastAccessed, size, alphabetical
    }

    public init(
        contentTypes: [String]? = nil,
        applications: [String]? = nil,
        dateRange: ClosedRange<Date>? = nil,
        isFavorite: Bool? = nil,
        isPinned: Bool? = nil,
        sortBy: SortOption = .createdAt
    ) {
        self.contentTypes = contentTypes
        self.applications = applications
        self.dateRange = dateRange
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.sortBy = sortBy
    }

    func buildSQL() -> (String, [DatabaseValueConvertible]) {
        var conditions: [String] = []
        var arguments: [DatabaseValueConvertible] = []

        if let contentTypes = contentTypes {
            let placeholders = Array(repeating: "?", count: contentTypes.count).joined(separator: ",")
            conditions.append("content_type IN (\(placeholders))")
            arguments.append(contentsOf: contentTypes)
        }

        if let dateRange = dateRange {
            conditions.append("created_at BETWEEN ? AND ?")
            arguments.append(dateRange.lowerBound.timeIntervalSince1970)
            arguments.append(dateRange.upperBound.timeIntervalSince1970)
        }

        if let isFavorite = isFavorite {
            conditions.append("is_favorite = ?")
            arguments.append(isFavorite)
        }

        if let isPinned = isPinned {
            conditions.append("is_pinned = ?")
            arguments.append(isPinned)
        }

        return (conditions.joined(separator: " AND "), arguments)
    }
}
