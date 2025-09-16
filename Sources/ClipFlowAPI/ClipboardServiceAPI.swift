import Foundation
import Combine
import ClipFlowCore

// MARK: - Clipboard Service API Protocol

@MainActor
public protocol ClipboardServiceAPI {

    // MARK: Core Operations

    /// Start monitoring clipboard changes
    func startMonitoring() async throws

    /// Stop monitoring clipboard
    func stopMonitoring() async

    /// Get current clipboard content
    func getCurrentClipboard() async -> ClipboardItem?

    /// Manual clipboard read (bypasses monitoring)
    func readClipboard() async throws -> ClipboardItem

    /// Write content to clipboard
    func writeToClipboard(_ item: ClipboardItem) async throws

    /// Paste content with optional transformation
    func paste(_ item: ClipboardItem,
               transform: TransformAction?) async throws

    // MARK: History Management

    /// Fetch clipboard history with pagination
    func getHistory(offset: Int,
                   limit: Int,
                   filter: HistoryFilter?) async throws -> [ClipboardItem]

    /// Get single item by ID
    func getItem(id: UUID) async throws -> ClipboardItem?

    /// Delete items (soft delete)
    func deleteItems(ids: [UUID]) async throws

    /// Permanently delete items
    func purgeItems(ids: [UUID]) async throws

    /// Clear all history
    func clearHistory(olderThan: Date?) async throws

    // MARK: Search

    /// Full-text search across history
    func search(query: String,
               scope: SearchScope,
               limit: Int) async throws -> [ClipboardItem]

    /// Get suggested searches
    func getSuggestions(for query: String) async -> [String]

    // MARK: Organization

    /// Pin/unpin items
    func togglePin(itemId: UUID) async throws

    /// Add tags to item
    func addTags(_ tags: Set<String>,
                 to itemId: UUID) async throws

    /// Mark as favorite
    func toggleFavorite(itemId: UUID) async throws

    // MARK: Statistics

    /// Get usage statistics
    func getStatistics() async -> ClipboardStatistics

    /// Get most used items
    func getFrequentItems(limit: Int) async -> [ClipboardItem]

    // MARK: Publishers for Reactive Updates

    var itemUpdates: AnyPublisher<ClipboardItem, Never> { get }
    var errors: AnyPublisher<ClipboardError, Never> { get }
    var statusUpdates: AnyPublisher<MonitorStatus, Never> { get }
}

// MARK: - Filter Types

public struct HistoryFilter: Sendable {
    public let contentTypes: [String]?
    public let applications: [String]?
    public let dateRange: ClosedRange<Date>?
    public let tags: [String]?
    public let isFavorite: Bool?
    public let isPinned: Bool?
    public let isDeleted: Bool?

    public init(
        contentTypes: [String]? = nil,
        applications: [String]? = nil,
        dateRange: ClosedRange<Date>? = nil,
        tags: [String]? = nil,
        isFavorite: Bool? = nil,
        isPinned: Bool? = nil,
        isDeleted: Bool? = false
    ) {
        self.contentTypes = contentTypes
        self.applications = applications
        self.dateRange = dateRange
        self.tags = tags
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.isDeleted = isDeleted
    }
}

public enum SearchScope: Sendable {
    case all
    case content
    case metadata
    case tags
    case applications
    case collections([UUID])
}

public enum TransformAction: String, CaseIterable, Sendable, Codable {
    case toUpperCase = "uppercase"
    case toLowerCase = "lowercase"
    case removeFormatting = "plain"
    case extractURLs = "urls"
    case extractEmails = "emails"
    case base64Encode = "base64"
    case base64Decode = "base64decode"
    case jsonFormat = "json"
    case xmlFormat = "xml"
    case trimWhitespace = "trim"

    public var displayName: String {
        switch self {
        case .toUpperCase: return "UPPERCASE"
        case .toLowerCase: return "lowercase"
        case .removeFormatting: return "Remove Formatting"
        case .extractURLs: return "Extract URLs"
        case .extractEmails: return "Extract Emails"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .jsonFormat: return "Format JSON"
        case .xmlFormat: return "Format XML"
        case .trimWhitespace: return "Trim Whitespace"
        }
    }
}

// MARK: - Status Types (already defined in ClipboardMonitorService)

public enum MonitorStatus {
    case stopped
    case monitoring
    case paused
    case error(ClipboardError)
}

public enum ClipboardError: Error {
    case accessDenied
    case processingFailed(Error)
    case unsupportedContent
    case encryptionFailed
    case storageFailed(Error)
    case networkError(Error)
    case invalidInput(String)
}

public struct ClipboardStatistics {
    public let totalItemsProcessed: Int
    public let detectionErrors: Int
    public let lastDetectionTime: Date?
    public let isMonitoring: Bool
    public let pollingInterval: TimeInterval
    public let averageProcessingTime: TimeInterval
    public let memoryUsage: Int64
    public let cacheHitRate: Double

    public init(
        totalItemsProcessed: Int,
        detectionErrors: Int,
        lastDetectionTime: Date?,
        isMonitoring: Bool,
        pollingInterval: TimeInterval,
        averageProcessingTime: TimeInterval = 0,
        memoryUsage: Int64 = 0,
        cacheHitRate: Double = 0
    ) {
        self.totalItemsProcessed = totalItemsProcessed
        self.detectionErrors = detectionErrors
        self.lastDetectionTime = lastDetectionTime
        self.isMonitoring = isMonitoring
        self.pollingInterval = pollingInterval
        self.averageProcessingTime = averageProcessingTime
        self.memoryUsage = memoryUsage
        self.cacheHitRate = cacheHitRate
    }
}