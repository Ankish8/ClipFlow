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
                t.column("tags", .text) // JSON array
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
                t.column("tags")
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

        return migrator
    }

    // MARK: - Database Operations

    public func write<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.write(block)
    }

    public func read<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.read(block)
    }

    // MARK: - Clipboard Items

    public func saveItem(_ item: ClipboardItem) async throws {
        try await write { db in
            var record = ClipboardItemRecord(from: item)
            try record.insert(db)

            // Update FTS index
            try db.execute(sql: """
                INSERT INTO items_fts (rowid, content_text, tags, application_name)
                VALUES (last_insert_rowid(), ?, ?, ?)
            """, arguments: [
                item.content.displayText,
                Array(item.tags).joined(separator: " "),
                item.source.applicationName ?? ""
            ])
        }
    }

    public func updateItem(_ item: ClipboardItem) async throws {
        try await write { db in
            var record = ClipboardItemRecord(from: item)
            try record.update(db)

            // Update FTS index
            try db.execute(sql: """
                UPDATE items_fts SET
                    content_text = ?,
                    tags = ?,
                    application_name = ?
                WHERE rowid = (SELECT rowid FROM clipboard_items WHERE id = ?)
            """, arguments: [
                item.content.displayText,
                Array(item.tags).joined(separator: " "),
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

    public func getItems(
        limit: Int = 100,
        offset: Int = 0,
        filter: ItemFilter? = nil
    ) async throws -> [ClipboardItem] {
        try await read { db in
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

            let records = try ClipboardItemRecord.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return try records.map { try $0.toClipboardItem() }
        }
    }

    public func searchItems(query: String, limit: Int = 50) async throws -> [ClipboardItem] {
        try await read { db in
            let sql = """
                SELECT ci.* FROM clipboard_items ci
                JOIN items_fts fts ON fts.rowid = ci.rowid
                WHERE items_fts MATCH ? AND ci.is_deleted = 0
                ORDER BY bm25(items_fts)
                LIMIT ?
            """

            let records = try ClipboardItemRecord.fetchAll(db, sql: sql, arguments: [query, limit])
            return try records.map { try $0.toClipboardItem() }
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
}

// MARK: - Item Filter

public struct ItemFilter {
    let contentTypes: [String]?
    let applications: [String]?
    let tags: [String]?
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
        tags: [String]? = nil,
        dateRange: ClosedRange<Date>? = nil,
        isFavorite: Bool? = nil,
        isPinned: Bool? = nil,
        sortBy: SortOption = .createdAt
    ) {
        self.contentTypes = contentTypes
        self.applications = applications
        self.tags = tags
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