import Foundation
import GRDB
import ClipFlowCore

// MARK: - ClipboardItemRecord

struct ClipboardItemRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var contentType: String
    var contentData: Data?
    var contentText: String?
    var metadata: String
    var source: String
    var timestamps: String
    var security: String
    var tags: String?
    var collectionIds: String?
    var isFavorite: Bool
    var isPinned: Bool
    var isDeleted: Bool
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval?
    var accessedAt: TimeInterval?
    var expiresAt: TimeInterval?
    var hash: String

    static let databaseTableName = "clipboard_items"

    init(from item: ClipboardItem) {
        self.id = item.id.uuidString
        self.contentType = item.content.contentType
        self.contentData = try? JSONEncoder().encode(item.content)
        self.contentText = item.content.displayText
        self.metadata = (try? JSONEncoder().encode(item.metadata).base64EncodedString()) ?? ""
        self.source = (try? JSONEncoder().encode(item.source).base64EncodedString()) ?? ""
        self.timestamps = (try? JSONEncoder().encode(item.timestamps).base64EncodedString()) ?? ""
        self.security = (try? JSONEncoder().encode(item.security).base64EncodedString()) ?? ""
        self.tags = item.tags.isEmpty ? nil : (try? JSONEncoder().encode(Array(item.tags)).base64EncodedString())
        self.collectionIds = item.collectionIds.isEmpty ? nil : (try? JSONEncoder().encode(Array(item.collectionIds)).base64EncodedString())
        self.isFavorite = item.isFavorite
        self.isPinned = item.isPinned
        self.isDeleted = item.isDeleted
        self.createdAt = item.timestamps.createdAt.timeIntervalSince1970
        self.modifiedAt = item.timestamps.modifiedAt?.timeIntervalSince1970
        self.accessedAt = item.timestamps.lastAccessedAt?.timeIntervalSince1970
        self.expiresAt = item.timestamps.expiresAt?.timeIntervalSince1970
        self.hash = item.metadata.hash
    }

    func toClipboardItem() throws -> ClipboardItem {
        let decoder = JSONDecoder()

        guard let contentData = contentData,
              let content = try? decoder.decode(ClipboardContent.self, from: contentData) else {
            throw DatabaseError.corruptedData("Failed to decode content")
        }

        guard let metadataData = Data(base64Encoded: metadata),
              let itemMetadata = try? decoder.decode(ItemMetadata.self, from: metadataData) else {
            throw DatabaseError.corruptedData("Failed to decode metadata")
        }

        guard let sourceData = Data(base64Encoded: source),
              let itemSource = try? decoder.decode(ItemSource.self, from: sourceData) else {
            throw DatabaseError.corruptedData("Failed to decode source")
        }

        guard let timestampsData = Data(base64Encoded: timestamps),
              let itemTimestamps = try? decoder.decode(ItemTimestamps.self, from: timestampsData) else {
            throw DatabaseError.corruptedData("Failed to decode timestamps")
        }

        guard let securityData = Data(base64Encoded: security),
              let itemSecurity = try? decoder.decode(SecurityMetadata.self, from: securityData) else {
            throw DatabaseError.corruptedData("Failed to decode security")
        }

        let itemTags: Set<String>
        if let tagsString = tags,
           let tagsData = Data(base64Encoded: tagsString),
           let decodedTags = try? decoder.decode([String].self, from: tagsData) {
            itemTags = Set(decodedTags)
        } else {
            itemTags = []
        }

        let itemCollectionIds: Set<UUID>
        if let collectionIdsString = collectionIds,
           let collectionIdsData = Data(base64Encoded: collectionIdsString),
           let decodedCollectionIds = try? decoder.decode([UUID].self, from: collectionIdsData) {
            itemCollectionIds = Set(decodedCollectionIds)
        } else {
            itemCollectionIds = []
        }

        guard let uuid = UUID(uuidString: id) else {
            throw DatabaseError.corruptedData("Invalid UUID")
        }

        return ClipboardItem(
            id: uuid,
            content: content,
            metadata: itemMetadata,
            source: itemSource,
            timestamps: itemTimestamps,
            security: itemSecurity,
            tags: itemTags,
            collectionIds: itemCollectionIds,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isDeleted: isDeleted
        )
    }
}

// MARK: - CollectionRecord

struct CollectionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var name: String
    var description: String?
    var icon: String
    var color: String
    var isShared: Bool
    var shareSettings: String?
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval

    static let databaseTableName = "collections"

    init(from collection: Collection) {
        self.id = collection.id.uuidString
        self.name = collection.name
        self.description = collection.description
        self.icon = collection.icon
        self.color = collection.color
        self.isShared = collection.isShared
        self.shareSettings = collection.shareSettings.flatMap { settings in
            try? JSONEncoder().encode(settings).base64EncodedString()
        }
        self.createdAt = collection.createdAt.timeIntervalSince1970
        self.modifiedAt = collection.modifiedAt.timeIntervalSince1970
    }

    func toCollection() throws -> Collection {
        let decoder = JSONDecoder()

        let settings: ShareSettings?
        if let shareSettingsString = shareSettings,
           let shareSettingsData = Data(base64Encoded: shareSettingsString) {
            settings = try? decoder.decode(ShareSettings.self, from: shareSettingsData)
        } else {
            settings = nil
        }

        guard let uuid = UUID(uuidString: id) else {
            throw DatabaseError.corruptedData("Invalid UUID")
        }

        return Collection(
            id: uuid,
            name: name,
            description: description,
            icon: icon,
            color: color,
            itemIds: [], // Will be populated separately
            isShared: isShared,
            shareSettings: settings,
            createdAt: Date(timeIntervalSince1970: createdAt),
            modifiedAt: Date(timeIntervalSince1970: modifiedAt)
        )
    }
}

// MARK: - SnippetRecord

struct SnippetRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var title: String
    var content: String
    var placeholders: String?
    var keyword: String?
    var category: String
    var usageCount: Int
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval

    static let databaseTableName = "snippets"

    init(from snippet: SnippetContent) {
        self.id = snippet.id.uuidString
        self.title = snippet.title
        self.content = snippet.content
        self.placeholders = snippet.placeholders.isEmpty ? nil :
            (try? JSONEncoder().encode(snippet.placeholders).base64EncodedString())
        self.keyword = snippet.keyword
        self.category = snippet.category
        self.usageCount = snippet.usageCount
        self.createdAt = Date().timeIntervalSince1970
        self.modifiedAt = Date().timeIntervalSince1970
    }

    func toSnippet() throws -> SnippetContent {
        let decoder = JSONDecoder()

        let snippetPlaceholders: [Placeholder]
        if let placeholdersString = placeholders,
           let placeholdersData = Data(base64Encoded: placeholdersString) {
            snippetPlaceholders = (try? decoder.decode([Placeholder].self, from: placeholdersData)) ?? []
        } else {
            snippetPlaceholders = []
        }

        guard let uuid = UUID(uuidString: id) else {
            throw DatabaseError.corruptedData("Invalid UUID")
        }

        return SnippetContent(
            id: uuid,
            title: title,
            content: content,
            placeholders: snippetPlaceholders,
            keyword: keyword,
            category: category,
            usageCount: usageCount
        )
    }
}

// MARK: - AutomationRuleRecord

struct AutomationRuleRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var name: String
    var triggerData: String
    var conditions: String?
    var actions: String
    var isEnabled: Bool
    var executionCount: Int
    var lastExecuted: TimeInterval?
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval

    static let databaseTableName = "automation_rules"

    func toAutomationRule() throws -> AutomationRule {
        guard let uuid = UUID(uuidString: id) else {
            throw DatabaseError.corruptedData("Invalid UUID")
        }

        // For now, return a placeholder AutomationRule
        // Full implementation would decode the JSON data
        return AutomationRule(
            id: uuid,
            name: name,
            trigger: .clipboardChange,
            conditions: [],
            actions: [],
            isEnabled: isEnabled
        )
    }
}

// MARK: - Database Errors

enum DatabaseError: Error {
    case corruptedData(String)
    case migrationFailed(String)
    case connectionFailed
    case queryFailed(String)
}

// MARK: - AutomationRule Placeholder

public struct AutomationRule: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let trigger: AutomationTrigger
    public let conditions: [AutomationCondition]
    public let actions: [AutomationAction]
    public let isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        trigger: AutomationTrigger,
        conditions: [AutomationCondition] = [],
        actions: [AutomationAction] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
        self.isEnabled = isEnabled
    }
}

public enum AutomationTrigger: Codable {
    case clipboardChange
    case applicationLaunch(bundleID: String)
    case timeInterval(seconds: Int)
    case hotkey(combination: String)
}

public struct AutomationCondition: Codable {
    public let type: ConditionType
    public let value: String
    public let operator: ComparisonOperator

    public init(type: ConditionType, value: String, operator: ComparisonOperator) {
        self.type = type
        self.value = value
        self.operator = `operator`
    }
}

public enum ConditionType: String, Codable {
    case contentType, application, textContains, size, age
}

public enum ComparisonOperator: String, Codable {
    case equals, contains, startsWith, endsWith, regex, greater, less
}

public enum AutomationAction: Codable {
    case transform(TransformAction)
    case notify(message: String)
    case copyToCollection(id: UUID)
    case delete
    case export(format: ExportFormat)
}

public enum TransformAction: String, Codable {
    case toUpperCase, toLowerCase, removeFormatting,
         extractURLs, extractEmails, base64Encode
}

public enum ExportFormat: String, Codable {
    case json, csv, txt, rtf, html
}