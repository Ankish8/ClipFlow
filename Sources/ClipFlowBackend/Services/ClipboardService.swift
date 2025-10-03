import Foundation
import AppKit
import Combine
import ClipFlowCore
import ClipFlowAPI

// MARK: - Clipboard Service Implementation

@MainActor
public class ClipboardService: ClipboardServiceAPI {
    public static let shared = ClipboardService()

    // Dependencies
    private let monitorService: ClipboardMonitorService
    private let storageService: StorageService
    private let tagService: TagService
    private let performanceMonitor: PerformanceMonitor

    // Publishers
    private let _itemUpdates = PassthroughSubject<ClipboardItem, Never>()
    private let _errors = PassthroughSubject<ClipboardError, Never>()
    private let _statusUpdates = CurrentValueSubject<MonitorStatus, Never>(.stopped)

    // State
    private var isInitialized = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.storageService = StorageService()
        self.tagService = TagService()
        self.performanceMonitor = PerformanceMonitor.shared
        self.monitorService = ClipboardMonitorService(
            storageService: storageService,
            performanceMonitor: performanceMonitor
        )

        Task {
            await initialize()
        }
    }

    // MARK: - Publishers

    public var itemUpdates: AnyPublisher<ClipboardItem, Never> {
        _itemUpdates.eraseToAnyPublisher()
    }

    public var errors: AnyPublisher<ClipboardError, Never> {
        _errors.eraseToAnyPublisher()
    }

    public var statusUpdates: AnyPublisher<MonitorStatus, Never> {
        _statusUpdates.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    private func initialize() async {
        guard !isInitialized else { return }

        // Set up monitor service subscriptions
        await setupMonitorSubscriptions()

        isInitialized = true
    }

    private func setupMonitorSubscriptions() async {
        // Subscribe to monitor updates
        monitorService.itemUpdates
            .sink { [weak self] item in
                self?._itemUpdates.send(item)
            }
            .store(in: &cancellables)

        monitorService.errors
            .sink { [weak self] error in
                self?._errors.send(error)
            }
            .store(in: &cancellables)

        monitorService.status
            .sink { [weak self] status in
                self?._statusUpdates.send(status)
            }
            .store(in: &cancellables)
    }

    // MARK: - Core Operations

    public func startMonitoring() async throws {
        await performanceMonitor.measure(operation: "start_monitoring") {
            await monitorService.startMonitoring()
        }
    }

    public func stopMonitoring() async {
        await performanceMonitor.measure(operation: "stop_monitoring") {
            await monitorService.stopMonitoring()
        }
    }

    public func getCurrentClipboard() async -> ClipboardItem? {
        return await performanceMonitor.measure(operation: "get_current_clipboard") {
            await monitorService.forceCheck()
        }
    }

    public func readClipboard() async throws -> ClipboardItem {
        return try await performanceMonitor.measure(operation: "read_clipboard") {
            guard let item = await monitorService.forceCheck() else {
                throw ClipboardError.unsupportedContent
            }
            return item
        }
    }

    public func writeToClipboard(_ item: ClipboardItem) async throws {
        try await performanceMonitor.measure(operation: "write_to_clipboard") {
            // Pause monitoring to prevent self-duplication
            monitorService.pauseMonitoring()

            // Notify monitor about internal write with item hash
            monitorService.notifyInternalWrite(hash: item.metadata.hash)

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            switch item.content {
            case .text(let textContent):
                pasteboard.setString(textContent.plainText, forType: .string)

            case .richText(let richContent):
                pasteboard.setData(richContent.rtfData, forType: .rtf)
                if let html = richContent.htmlString {
                    pasteboard.setString(html, forType: .html)
                }

            case .image(let imageContent):
                // Write raw image data directly to prevent file path issues
                // CRITICAL: We must write ONLY image data types to prevent apps from
                // reading file paths that may have existed when the image was captured
                switch imageContent.format {
                case .png:
                    // Write PNG data directly
                    pasteboard.setData(imageContent.data, forType: .png)
                case .tiff:
                    // Write TIFF data directly
                    pasteboard.setData(imageContent.data, forType: .tiff)
                case .jpeg, .gif, .bmp, .heif, .webp, .svg:
                    // For formats without direct pasteboard support, convert to PNG
                    if let image = NSImage(data: imageContent.data),
                       let tiffData = image.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                        pasteboard.setData(pngData, forType: .png)
                    }
                    // If conversion fails, we just skip (could log error here)
                }

                // IMPORTANT: Also write as NSImage to ensure compatibility with all apps
                // This prevents apps from falling back to reading file URLs
                if let image = NSImage(data: imageContent.data) {
                    // declareTypes clears the pasteboard and sets only the types we specify
                    // This removes any stale file-url references
                    let types: [NSPasteboard.PasteboardType] = imageContent.format == .png ? [.png, .tiff] : [.tiff]
                    pasteboard.addTypes(types, owner: nil)

                    // Write both the raw data AND the NSImage representation
                    if imageContent.format == .png {
                        pasteboard.setData(imageContent.data, forType: .png)
                    }
                    // Always write TIFF as fallback for maximum compatibility
                    if let tiffData = image.tiffRepresentation {
                        pasteboard.setData(tiffData, forType: .tiff)
                    }
                }

            case .file(let fileContent):
                pasteboard.writeObjects(fileContent.urls as [NSURL])

            case .link(let linkContent):
                pasteboard.setString(linkContent.url.absoluteString, forType: .URL)
                pasteboard.setString(linkContent.url.absoluteString, forType: .string)

            case .code(let codeContent):
                pasteboard.setString(codeContent.code, forType: .string)

            case .color(let colorContent):
                let nsColor = NSColor(
                    red: colorContent.red,
                    green: colorContent.green,
                    blue: colorContent.blue,
                    alpha: colorContent.alpha
                )
                pasteboard.writeObjects([nsColor])

            case .snippet(let snippetContent):
                pasteboard.setString(snippetContent.content, forType: .string)

            case .multiple(let multiContent):
                // Write the first item for now
                if let firstItem = multiContent.items.first {
                    let tempItem = ClipboardItem(
                        content: firstItem,
                        metadata: item.metadata,
                        source: item.source
                    )
                    try await writeToClipboard(tempItem)
                }
            }

            // Resume monitoring after a brief delay to ensure clipboard write completes
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                monitorService.resumeMonitoring()
            }
        }
    }

    public func paste(_ item: ClipboardItem, transform: TransformAction?) async throws {
        try await performanceMonitor.measure(operation: "paste_item") {
            var itemToPaste = item

            // Apply transformation if requested
            if let transform = transform {
                itemToPaste = try await applyTransform(transform, to: item)
            }

            // Write to clipboard
            try await writeToClipboard(itemToPaste)

            // CRITICAL: Wait for clipboard write to fully complete before pasting
            // macOS clipboard operations are asynchronous and need time to propagate
            try? await Task.sleep(for: .milliseconds(50))

            // Simulate paste command (using Macboard's proven approach)
            await MainActor.run {
                let source = CGEventSource(stateID: .combinedSessionState)
                // Disable local keyboard events while pasting for reliability
                source?.setLocalEventsFilterDuringSuppressionState(
                    [.permitLocalMouseEvents, .permitSystemDefinedEvents],
                    state: .eventSuppressionStateSuppressionInterval
                )

                let pasteKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
                let pasteKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

                pasteKeyDown?.flags = .maskCommand
                pasteKeyUp?.flags = .maskCommand

                pasteKeyDown?.post(tap: .cgSessionEventTap)
                pasteKeyUp?.post(tap: .cgSessionEventTap)
            }
        }
    }

    // MARK: - History Management

    public func getHistory(
        offset: Int,
        limit: Int,
        filter: HistoryFilter?
    ) async throws -> [ClipboardItem] {
        return try await performanceMonitor.measure(operation: "get_history") {
            let itemFilter = convertToItemFilter(filter)
            return try await storageService.getItems(
                limit: limit,
                offset: offset,
                filter: itemFilter
            )
        }
    }

    public func getItem(id: UUID) async throws -> ClipboardItem? {
        return try await performanceMonitor.measure(operation: "get_item") {
            return try await storageService.getItem(id: id)
        }
    }

    public func deleteItems(ids: [UUID]) async throws {
        try await performanceMonitor.measure(operation: "delete_items") {
            try await storageService.deleteItems(ids: ids, permanent: false)
        }
    }

    public func purgeItems(ids: [UUID]) async throws {
        try await performanceMonitor.measure(operation: "purge_items") {
            try await storageService.deleteItems(ids: ids, permanent: true)
        }
    }

    public func clearHistory(olderThan date: Date?) async throws {
        try await performanceMonitor.measure(operation: "clear_history") {
            let cutoffDate = date ?? Date.distantPast
            let filter = HistoryFilter(
                dateRange: cutoffDate...Date.distantFuture,
                isDeleted: false
            )

            let items = try await getHistory(offset: 0, limit: Int.max, filter: filter)
            let idsToDelete = items.map { $0.id }

            try await deleteItems(ids: idsToDelete)
        }
    }

    // MARK: - Search

    public func search(
        query: String,
        scope: SearchScope,
        limit: Int
    ) async throws -> [ClipboardItem] {
        return try await performanceMonitor.measure(operation: "search_items") {
            // For now, use basic search - could be enhanced based on scope
            return try await storageService.searchItems(query: query, limit: limit)
        }
    }

    public func getSuggestions(for query: String) async -> [String] {
        return await performanceMonitor.measure(operation: "get_suggestions") {
            // Simple implementation - could be enhanced with ML
            guard query.count >= 2 else { return [] }

            let commonSuggestions = [
                "password", "email", "url", "code", "image", "file",
                "today", "yesterday", "last week", "pinned", "favorites"
            ]

            return commonSuggestions.filter { suggestion in
                suggestion.lowercased().contains(query.lowercased())
            }
        }
    }

    // MARK: - Organization

    public func togglePin(itemId: UUID) async throws {
        try await performanceMonitor.measure(operation: "toggle_pin") {
            guard var item = try await storageService.getItem(id: itemId) else {
                throw ClipboardError.invalidInput("Item not found")
            }

            item.isPinned.toggle()
            try await storageService.updateItem(item)
            _itemUpdates.send(item)
        }
    }


    public func toggleFavorite(itemId: UUID) async throws {
        try await performanceMonitor.measure(operation: "toggle_favorite") {
            guard var item = try await storageService.getItem(id: itemId) else {
                throw ClipboardError.invalidInput("Item not found")
            }

            item.isFavorite.toggle()
            try await storageService.updateItem(item)
            _itemUpdates.send(item)
        }
    }

    // MARK: - Statistics

    public func getStatistics() async -> ClipboardStatistics {
        return await performanceMonitor.measure(operation: "get_statistics") {
            let monitorStats = monitorService.getStatistics()
            let performanceStats = await performanceMonitor.getStatistics()
            let storageStats = await storageService.getStorageStatistics()

            return ClipboardStatistics(
                totalItemsProcessed: monitorStats.totalItemsProcessed,
                detectionErrors: monitorStats.detectionErrors,
                lastDetectionTime: monitorStats.lastDetectionTime,
                isMonitoring: monitorStats.isMonitoring,
                pollingInterval: monitorStats.pollingInterval,
                averageProcessingTime: performanceStats.averageDuration,
                memoryUsage: Int64(storageStats.totalSizeBytes),
                cacheHitRate: storageStats.cacheStats.hitRate
            )
        }
    }

    public func getFrequentItems(limit: Int) async -> [ClipboardItem] {
        return await performanceMonitor.measure(operation: "get_frequent_items") {
            // Simple implementation based on access count
            // In a real implementation, you'd track access frequency
            do {
                let filter = HistoryFilter(isPinned: true) // Use pinned as proxy for frequent
                return try await getHistory(offset: 0, limit: limit, filter: filter)
            } catch {
                _errors.send(.storageFailed(error))
                return []
            }
        }
    }

    // MARK: - Private Helpers

    private func applyTransform(_ transform: TransformAction, to item: ClipboardItem) async throws -> ClipboardItem {
        let transformedContent: ClipboardContent

        switch item.content {
        case .text(let textContent):
            transformedContent = .text(TextContent(
                plainText: applyTextTransform(transform, to: textContent.plainText),
                encoding: textContent.encoding,
                language: textContent.language,
                isEmail: textContent.isEmail,
                isPhoneNumber: textContent.isPhoneNumber,
                isURL: textContent.isURL
            ))

        case .richText(let richContent):
            transformedContent = .text(TextContent(
                plainText: applyTextTransform(transform, to: richContent.plainTextFallback)
            ))

        case .code(let codeContent):
            transformedContent = .code(CodeContent(
                code: applyTextTransform(transform, to: codeContent.code),
                language: codeContent.language,
                syntaxHighlightedData: codeContent.syntaxHighlightedData,
                repository: codeContent.repository
            ))

        default:
            throw ClipboardError.unsupportedContent
        }

        let metadata = ItemMetadata.generate(for: transformedContent)

        return ClipboardItem(
            id: UUID(),
            content: transformedContent,
            metadata: metadata,
            source: item.source,
            timestamps: ItemTimestamps(),
            security: item.security,
            collectionIds: item.collectionIds,
            isFavorite: item.isFavorite,
            isPinned: item.isPinned,
            isDeleted: item.isDeleted
        )
    }

    private func applyTextTransform(_ transform: TransformAction, to text: String) -> String {
        switch transform {
        case .toUpperCase:
            return text.uppercased()
        case .toLowerCase:
            return text.lowercased()
        case .removeFormatting:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .extractURLs:
            return extractURLs(from: text).joined(separator: "\n")
        case .extractEmails:
            return extractEmails(from: text).joined(separator: "\n")
        case .base64Encode:
            return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: text) else { return text }
            return String(data: data, encoding: .utf8) ?? text
        case .jsonFormat:
            return formatJSON(text)
        case .xmlFormat:
            return formatXML(text)
        case .trimWhitespace:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func extractURLs(from text: String) -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        return matches?.compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        } ?? []
    }

    private func extractEmails(from text: String) -> [String] {
        let emailRegex = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        let matches = text.matches(of: try! Regex(emailRegex))
        return matches.map { String(text[$0.range]) }
    }

    private func formatJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let formattedString = String(data: formatted, encoding: .utf8) else {
            return text
        }
        return formattedString
    }

    private func formatXML(_ text: String) -> String {
        // Simple XML formatting - could be enhanced
        return text.replacingOccurrences(of: "><", with: ">\n<")
    }

    private func convertToItemFilter(_ historyFilter: HistoryFilter?) -> ItemFilter? {
        guard let filter = historyFilter else { return nil }

        return ItemFilter(
            contentTypes: filter.contentTypes,
            applications: filter.applications,
            dateRange: filter.dateRange,
            isFavorite: filter.isFavorite,
            isPinned: filter.isPinned
        )
    }

    // MARK: - Convenience Methods for UI

    public func getRecentItems(limit: Int) async throws -> [ClipboardItem] {
        return try await getHistory(offset: 0, limit: limit, filter: nil)
    }

    public func getCollections() async throws -> [Collection] {
        // Collections not implemented yet - return empty array for v1
        return []
    }

    public func pasteItem(_ item: ClipboardItem) async {
        do {
            try await paste(item, transform: nil)
        } catch {
            _errors.send(.processingFailed(error))
        }
    }

    public func addItemToCollection(_ itemId: UUID, collectionId: UUID) async throws {
        // Collections not implemented yet - no-op for v1
    }

    public func searchItems(query: String, limit: Int) async throws -> [ClipboardItem] {
        return try await search(query: query, scope: .all, limit: limit)
    }

    public func deleteItem(_ itemId: UUID) async throws {
        try await deleteItems(ids: [itemId])
    }

    // MARK: - Tag Management

    public func createTag(_ tag: Tag) async throws -> Tag {
        return try await tagService.createTag(tag)
    }

    public func getAllTags() async throws -> [Tag] {
        return try await tagService.getAllTags()
    }

    public func getTag(id: UUID) async throws -> Tag? {
        return try await tagService.getTag(id: id)
    }

    public func updateTag(_ tag: Tag) async throws {
        try await tagService.updateTag(tag)
    }

    public func deleteTag(id: UUID) async throws {
        try await tagService.deleteTag(id: id)
    }

    public func assignTag(tagId: UUID, to itemId: UUID) async throws {
        try await tagService.assignTag(tagId: tagId, to: itemId)
    }

    public func unassignTag(tagId: UUID, from itemId: UUID) async throws {
        try await tagService.unassignTag(tagId: tagId, from: itemId)
    }

    public func getTagsForItem(itemId: UUID) async throws -> [Tag] {
        return try await tagService.getTagsForItem(itemId: itemId)
    }

    public func getItemsWithTag(tagId: UUID) async throws -> [UUID] {
        return try await tagService.getItemsWithTag(tagId: tagId)
    }

    public func getTagStatistics() async throws -> TagStatistics {
        return try await tagService.getTagStatistics()
    }

    public func searchTags(query: String) async throws -> [Tag] {
        return try await tagService.searchTags(query: query)
    }
}