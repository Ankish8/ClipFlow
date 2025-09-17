import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers
import ClipFlowCore
import ClipFlowAPI
import NaturalLanguage

// MARK: - Clipboard Monitor Actor
/// High-performance, thread-safe clipboard monitoring service that delivers sub-100ms response times
@MainActor
class ClipboardMonitorActor {
    // MARK: - State

    private var lastChangeCount: Int = 0
    private var lastHash: String = ""
    private var isMonitoring = false
    private var pollingInterval: TimeInterval = 0.1 // 100ms for optimal responsiveness

    // Performance tracking
    private var totalItemsProcessed: Int = 0
    private var detectionErrors: Int = 0
    private var lastDetectionTime: Date?
    private var averageProcessingTime: TimeInterval = 0.0

    // Memory pressure handling
    private var isUnderMemoryPressure = false
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // Dependencies
    private let storageService: StorageService
    private let performanceMonitor: PerformanceMonitor
    private let cacheManager: CacheManager

    // MARK: - Publishers
    private let itemSubject = PassthroughSubject<ClipboardItem, Never>()
    private let errorSubject = PassthroughSubject<ClipboardError, Never>()
    private let statusSubject = CurrentValueSubject<MonitorStatus, Never>(.stopped)

    // MARK: - Initialization

    init(
        storageService: StorageService,
        performanceMonitor: PerformanceMonitor,
        cacheManager: CacheManager
    ) {
        self.storageService = storageService
        self.performanceMonitor = performanceMonitor
        self.cacheManager = cacheManager

        Task {
            await setupMemoryPressureMonitoring()
        }
    }

    // MARK: - Public Interface

    func startMonitoring(interval: TimeInterval = 0.1) async {
        guard !isMonitoring else { return }

        await performanceMonitor.measure(operation: "start_monitoring") {
            self.isMonitoring = true
            self.pollingInterval = interval

            // Get initial state
            self.lastChangeCount = NSPasteboard.general.changeCount

            // Update status
            self.statusSubject.send(.monitoring)

            // Use Task for periodic checking instead of Timer to avoid Sendable issues
            Task {
                while self.isMonitoring {
                    await self.checkClipboard()
                    try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))
                }
            }
        }
    }

    func stopMonitoring() async {
        guard isMonitoring else { return }

        isMonitoring = false

        self.statusSubject.send(.stopped)
    }

    func forceCheck() async -> ClipboardItem? {
        return await performanceMonitor.measure(operation: "force_check") {
            await checkClipboard(force: true)
        }
    }

    func getStatistics() async -> ClipboardStatistics {
        ClipboardStatistics(
            totalItemsProcessed: totalItemsProcessed,
            detectionErrors: detectionErrors,
            lastDetectionTime: lastDetectionTime,
            isMonitoring: isMonitoring,
            pollingInterval: pollingInterval,
            averageProcessingTime: averageProcessingTime,
            memoryUsage: Int64(ProcessInfo.processInfo.physicalMemory),
            cacheHitRate: await cacheManager.hitRate
        )
    }

    func updatePollingInterval(_ interval: TimeInterval) async {
        pollingInterval = interval
        if isMonitoring {
            await stopMonitoring()
            await startMonitoring(interval: interval)
        }
    }

    func isCurrentlyMonitoring() -> Bool {
        isMonitoring
    }

    // MARK: - Publishers Access (MainActor)

    @MainActor
    func getItemUpdates() -> AnyPublisher<ClipboardItem, Never> {
        itemSubject.eraseToAnyPublisher()
    }

    @MainActor
    func getErrors() -> AnyPublisher<ClipboardError, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    @MainActor
    func getStatus() -> AnyPublisher<MonitorStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    // MARK: - Core Monitoring Logic

    @discardableResult
    private func checkClipboard(force: Bool = false) async -> ClipboardItem? {
        let startTime = Date()

        let changeCount = NSPasteboard.general.changeCount

        guard force || changeCount != lastChangeCount else { return nil }
        lastChangeCount = changeCount

        do {
            // Memory pressure check
            if isUnderMemoryPressure && !force {
                await handleMemoryPressure()
                return nil
            }

            // Privacy compliance check (macOS Sequoia)
            let isCompliant = self.checkPrivacyCompliance(NSPasteboard.general)
            if !isCompliant {
                return nil
            }

            // Check cache first for performance
            let pasteboardHash = self.generatePasteboardHash(NSPasteboard.general)
            if !force && pasteboardHash == lastHash {
                return nil
            }

            if let cachedItem = await cacheManager.getCachedItem(for: pasteboardHash) {
                lastHash = pasteboardHash
                await notifyItemFound(cachedItem)
                return cachedItem
            }

            // Process clipboard content with autoreleasepool for memory efficiency
            let item = await withMemoryManagement {
                await processClipboardContent(NSPasteboard.general)
            }

            guard let clipboardItem = item else { return nil }

            lastHash = pasteboardHash

            // Apply security checks
            let secureItem = await applySecurityChecks(clipboardItem)

            // Store the item
            try await storageService.saveItem(secureItem)

            // Cache the item for performance
            await cacheManager.cacheItem(secureItem, hash: pasteboardHash)

            // Update statistics
            totalItemsProcessed += 1
            lastDetectionTime = Date()
            updateAverageProcessingTime(startTime: startTime)

            // Notify subscribers
            await notifyItemFound(secureItem)

            return secureItem

        } catch {
            detectionErrors += 1
            let clipboardError = ClipboardError.processingFailed(error)
            await notifyError(clipboardError)
            return nil
        }
    }

    // MARK: - Privacy Compliance (macOS Sequoia)

    @MainActor
    private func checkPrivacyCompliance(_ pasteboard: NSPasteboard) -> Bool {
        // Check for concealed content (password manager data)
        if pasteboard.types?.contains(.init("org.nspasteboard.ConcealedType")) == true {
            return false
        }

        // Check for transient content
        if pasteboard.types?.contains(.init("org.nspasteboard.TransientType")) == true {
            return false
        }

        // Use the new privacy-safe method to check content availability
        if #available(macOS 15.4, *) {
            return pasteboard.canReadObject(forClasses: [NSString.self, NSImage.self, NSURL.self], options: nil)
        }

        return true
    }

    // MARK: - Memory Management

    private func withMemoryManagement<T>(_ operation: () async -> T) async -> T {
        // Use simplified memory management without autoreleasepool for async operations
        return await operation()
    }

    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.global(qos: .utility)
        )

        memoryPressureSource?.setEventHandler { [weak self] in
            Task {
                await self?.handleMemoryPressureEvent()
            }
        }

        memoryPressureSource?.resume()
    }

    private func handleMemoryPressureEvent() async {
        isUnderMemoryPressure = true

        // Reduce polling frequency during memory pressure
        if isMonitoring && pollingInterval < 0.5 {
            await updatePollingInterval(0.5) // Slow down to 500ms
        }

        // Clear cache to free memory
        await cacheManager.clearCache()

        // Schedule memory pressure relief
        Task.detached {
            try? await Task.sleep(for: .seconds(30))
            await self.relieveMemoryPressure()
        }
    }

    private func handleMemoryPressure() async {
        // Aggressive memory cleanup
        await cacheManager.evictLeastRecentlyUsed(percentage: 0.5)
    }

    private func relieveMemoryPressure() async {
        isUnderMemoryPressure = false

        // Restore normal polling frequency
        if isMonitoring && pollingInterval > 0.1 {
            await updatePollingInterval(0.1) // Back to 100ms
        }
    }

    // MARK: - Content Processing

    private func processClipboardContent(_ pasteboard: NSPasteboard) async -> ClipboardItem? {
        guard let types = pasteboard.types, !types.isEmpty else { return nil }

        let content: ClipboardContent?

        // Priority order for content detection (optimized for performance)
        if types.contains(.png) || types.contains(.tiff) {
            content = await self.processImageContent(pasteboard)
        } else if types.contains(.fileURL) {
            content = await self.processFileContent(pasteboard)
        } else if types.contains(.URL) {
            content = await self.processURLContent(pasteboard)
        } else if types.contains(.rtf) {
            content = await self.processRichTextContent(pasteboard)
        } else if types.contains(.string) {
            content = await self.processTextContent(pasteboard)
        } else if types.contains(.color) {
            content = await self.processColorContent(pasteboard)
        } else {
            content = await self.processGenericContent(pasteboard, types: types)
        }

        guard let clipboardContent = content else { return nil }

        let metadata = ItemMetadata.generate(for: clipboardContent)
        let source = await self.getCurrentApplicationInfo()

        return ClipboardItem(
            content: clipboardContent,
            metadata: metadata,
            source: source
        )
    }

    private func processImageContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        let image = NSImage(pasteboard: pasteboard)
        guard let validImage = image else {
            return nil
        }

        // Determine the best representation with memory efficiency
        var imageData: Data?
        var format: ImageFormat = .png

        if let pngData = pasteboard.data(forType: .png) {
            imageData = pngData
            format = .png
        } else if let tiffData = validImage.tiffRepresentation {
            // Convert TIFF to PNG for better compression
            if let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                imageData = pngData
                format = .png
            } else {
                imageData = tiffData
                format = .tiff
            }
        }

        guard let data = imageData else { return nil }

        // Generate thumbnail efficiently
        let thumbnailPath = await self.generateOptimizedThumbnail(for: validImage)

        // Extract color palette (async for performance)
        let colorPalette = await self.extractColorPalette(from: validImage)

        // Check for transparency efficiently
        let hasTransparency = await self.checkTransparency(image: validImage)

        return ClipboardContent.image(ImageContent(
            data: data,
            format: format,
            dimensions: validImage.size,
            thumbnailPath: thumbnailPath,
            colorPalette: colorPalette,
            hasTransparency: hasTransparency
        ))
    }

    private func processTextContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        let text = pasteboard.string(forType: .string)
        guard let validText = text else {
            return nil
        }

        let language = await self.detectLanguage(validText)
        let textContent = TextContent(
            plainText: validText,
            language: language,
            isEmail: validText.isValidEmail,
            isPhoneNumber: validText.isValidPhoneNumber,
            isURL: validText.isValidURL
        )

        // Intelligent code detection
        if let detectedLanguage = await self.detectProgrammingLanguage(validText) {
            return .code(CodeContent(code: validText, language: detectedLanguage))
        }

        return .text(textContent)
    }

    private func processRichTextContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        let rtfData = await MainActor.run { pasteboard.data(forType: .rtf) }
        guard let validRtfData = rtfData else {
            return nil
        }

        return await MainActor.run {

            var htmlString: String?
            var attributedStringData: Data?
            var plainTextFallback = ""

            // Get HTML representation if available
            if let html = pasteboard.string(forType: .html) {
                htmlString = html
            }

            // Process attributed string with memory management
            if let attrString = NSAttributedString(rtf: validRtfData, documentAttributes: nil) {
                attributedStringData = try? NSKeyedArchiver.archivedData(
                    withRootObject: attrString,
                    requiringSecureCoding: true
                )
                plainTextFallback = attrString.string
            }

            // Fallback to plain text
            if plainTextFallback.isEmpty {
                plainTextFallback = pasteboard.string(forType: .string) ?? "Rich text content"
            }

            return ClipboardContent.richText(RichTextContent(
                rtfData: validRtfData,
                htmlString: htmlString,
                attributedStringData: attributedStringData ?? Data(),
                plainTextFallback: plainTextFallback
            ))
        }
    }

    private func processFileContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        let urls = await MainActor.run { pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] }
        guard let validUrls = urls else {
            return nil
        }

        return await MainActor.run {

            let fileURLs = validUrls.filter { $0.isFileURL }
            guard !fileURLs.isEmpty else { return nil }

            // Calculate total size efficiently
            let totalSize = fileURLs.reduce(Int64(0)) { sum, url in
                do {
                    let resources = try url.resourceValues(forKeys: [.fileSizeKey])
                    return sum + Int64(resources.fileSize ?? 0)
                } catch {
                    return sum
                }
            }

            let fileName = fileURLs.count == 1 ?
                fileURLs.first!.lastPathComponent :
                "\(fileURLs.count) files"

            let fileType = fileURLs.first?.pathExtension ?? "mixed"
            let isDirectory = fileURLs.allSatisfy { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }

            return ClipboardContent.file(FileContent(
                urls: fileURLs,
                fileName: fileName,
                fileSize: totalSize,
                fileType: fileType,
                isDirectory: isDirectory
            ))
        }
    }

    private func processURLContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        let urlString = await MainActor.run { pasteboard.string(forType: .URL) }
        guard let validUrlString = urlString,
              let url = URL(string: validUrlString) else {
            return nil
        }

        return await MainActor.run {

            // Fetch metadata asynchronously without blocking
            Task.detached {
                _ = await self.fetchURLMetadata(url)
                // Could update the cached item with metadata later
            }

            return ClipboardContent.link(LinkContent(
                url: url,
                title: nil, // Will be updated asynchronously
                description: nil,
                faviconData: nil,
                previewImageData: nil
            ))
        }
    }

    private func processColorContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        let color = await MainActor.run { NSColor(from: pasteboard) }
        guard let validColor = color else {
            return nil
        }
        return ClipboardContent.color(ColorContent(nsColor: validColor))
    }

    private func processGenericContent(_ pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) async -> ClipboardContent? {
        var items: [ClipboardContent] = []

        // Process only the first few types for performance
        for type in types.prefix(3) {
            if let data = pasteboard.data(forType: type) {
                if type == .string, let text = String(data: data, encoding: .utf8) {
                    items.append(.text(TextContent(plainText: text)))
                }
            }
        }

        if items.count > 1 {
            return .multiple(MultiContent(
                items: items,
                description: "Multiple items (\(items.count))"
            ))
        }

        return items.first
    }

    // MARK: - Helper Methods

    @MainActor
    private func generatePasteboardHash(_ pasteboard: NSPasteboard) -> String {
        let changeCount = pasteboard.changeCount
        let typeCount = pasteboard.types?.count ?? 0
        return "\(changeCount)-\(typeCount)"
    }

    private func applySecurityChecks(_ item: ClipboardItem) async -> ClipboardItem {
        // Security features removed for v1 - no processing needed
        return item
    }

    private func getCurrentApplicationInfo() async -> ItemSource {
        return await MainActor.run {
            let workspace = NSWorkspace.shared
            let runningApps = workspace.runningApplications

            if let frontApp = runningApps.first(where: { $0.isActive }) {
                return ItemSource(
                    applicationBundleID: frontApp.bundleIdentifier,
                    applicationName: frontApp.localizedName,
                    applicationIcon: frontApp.icon?.tiffRepresentation
                )
            }

            return ItemSource()
        }
    }

    private func generateOptimizedThumbnail(for image: NSImage) async -> String {
        return await Task.detached {
            autoreleasepool {
                let thumbnailSize = NSSize(width: 200, height: 200)

                // Create thumbnail with high performance
                let thumbnail = NSImage(size: thumbnailSize)
                thumbnail.lockFocus()
                defer { thumbnail.unlockFocus() }

                image.draw(
                    in: NSRect(origin: .zero, size: thumbnailSize),
                    from: NSRect(origin: .zero, size: image.size),
                    operation: .sourceOver,
                    fraction: 1.0
                )

                // Save to cache directory
                let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                let thumbnailDir = cacheDir.appendingPathComponent("ClipFlow/thumbnails", isDirectory: true)

                do {
                    try FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)
                    let thumbnailPath = thumbnailDir.appendingPathComponent("\(UUID().uuidString).png")

                    if let tiffData = thumbnail.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                        try pngData.write(to: thumbnailPath)
                        return thumbnailPath.path
                    }
                } catch {
                    print("Failed to generate thumbnail: \(error)")
                }

                return ""
            }
        }.value
    }

    private func extractColorPalette(from image: NSImage) async -> [String] {
        // Simplified color extraction for performance
        // In production, you would use more sophisticated algorithms
        return []
    }

    private func checkTransparency(image: NSImage) async -> Bool {
        return await Task.detached {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return false
            }

            let alphaInfo = cgImage.alphaInfo
            return alphaInfo == .first || alphaInfo == .last ||
                   alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
        }.value
    }

    private func detectLanguage(_ text: String) async -> String? {
        if #available(macOS 12.0, *) {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            return recognizer.dominantLanguage?.rawValue
        }
        return nil
    }

    private func detectProgrammingLanguage(_ text: String) async -> String? {
        let codeIndicators = [
            ("swift", ["func ", "var ", "let ", "import ", "class ", "struct ", "@"]),
            ("javascript", ["function ", "const ", "let ", "var ", "=> ", "console.log", "import "]),
            ("typescript", ["interface ", "type ", "export ", "import ", ": string", ": number"]),
            ("python", ["def ", "import ", "from ", "class ", "if __name__", "print("]),
            ("java", ["public class", "private ", "public static void main", "import java"]),
            ("html", ["<html", "<div", "<span", "<!DOCTYPE", "<head>", "<body>"]),
            ("css", ["{", "}", ":", ";", "px", "margin:", "padding:", "color:"]),
            ("json", ["{\"", "\":", "[{", "}]", "null", "true", "false"]),
            ("xml", ["<?xml", "<!", "</", "/>"]),
            ("sql", ["SELECT ", "FROM ", "WHERE ", "INSERT ", "UPDATE ", "DELETE "])
        ]

        let lowercasedText = text.lowercased()

        for (language, indicators) in codeIndicators {
            let matchCount = indicators.reduce(0) { count, indicator in
                count + lowercasedText.components(separatedBy: indicator.lowercased()).count - 1
            }

            if matchCount >= 2 {
                return language
            }
        }

        return nil
    }

    private func fetchURLMetadata(_ url: URL) async -> (title: String?, description: String?, favicon: Data?, preview: Data?) {
        // Async URL metadata fetching - would implement actual fetching
        return (nil, nil, nil, nil)
    }

    private func updateAverageProcessingTime(startTime: Date) {
        let processingTime = Date().timeIntervalSince(startTime)
        averageProcessingTime = (averageProcessingTime + processingTime) / 2.0
    }

    // MARK: - Notification Helpers

    private func notifyItemFound(_ item: ClipboardItem) async {
        self.itemSubject.send(item)
    }

    private func notifyError(_ error: ClipboardError) async {
        self.errorSubject.send(error)
    }

    deinit {
        memoryPressureSource?.cancel()
    }
}

// MARK: - Supporting Types

// MonitorStatus is defined in ClipFlowAPI

// ClipboardStatistics is defined in ClipFlowAPI

// ClipboardError is defined in ClipFlowAPI

