import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers
import ClipFlowCore
import ClipFlowAPI
import NaturalLanguage

// MARK: - Clipboard Monitor Service

@MainActor
public class ClipboardMonitorService {
    // MARK: - Properties

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastHash: String = ""
    private var isMonitoring = false
    private var pollingInterval: TimeInterval = 0.15

    // Publishers for reactive updates
    private let itemSubject = PassthroughSubject<ClipboardItem, Never>()
    private let errorSubject = PassthroughSubject<ClipboardError, Never>()
    private let statusSubject = CurrentValueSubject<MonitorStatus, Never>(.stopped)

    // Dependencies
    private let storageService: StorageService
    private let performanceMonitor: PerformanceMonitor

    // Statistics
    private var totalItemsProcessed: Int = 0
    private var detectionErrors: Int = 0
    private var lastDetectionTime: Date?

    // MARK: - Public Publishers

    public var itemUpdates: AnyPublisher<ClipboardItem, Never> {
        itemSubject.eraseToAnyPublisher()
    }

    public var errors: AnyPublisher<ClipboardError, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    public var status: AnyPublisher<MonitorStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    public init(
        storageService: StorageService,
        performanceMonitor: PerformanceMonitor = PerformanceMonitor.shared
    ) {
        self.storageService = storageService
        self.performanceMonitor = performanceMonitor
    }

    // MARK: - Public Methods

    public func startMonitoring(interval: TimeInterval = 0.15) async {
        guard !isMonitoring else { return }

        await performanceMonitor.measure(operation: "start_monitoring") {
            self.isMonitoring = true
            self.pollingInterval = interval
            self.lastChangeCount = NSPasteboard.general.changeCount

            await MainActor.run {
                self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                    Task {
                        await self.checkClipboard()
                    }
                }
            }

            self.statusSubject.send(.monitoring)
        }
    }

    public func stopMonitoring() async {
        guard isMonitoring else { return }

        let timerToInvalidate = timer
        timer = nil

        await MainActor.run {
            timerToInvalidate?.invalidate()
        }

        isMonitoring = false
        statusSubject.send(.stopped)
    }

    public func forceCheck() async -> ClipboardItem? {
        return await performanceMonitor.measure(operation: "force_check") {
            await checkClipboard(force: true)
        }
    }

    public func getStatistics() -> ClipboardStatistics {
        ClipboardStatistics(
            totalItemsProcessed: totalItemsProcessed,
            detectionErrors: detectionErrors,
            lastDetectionTime: lastDetectionTime,
            isMonitoring: isMonitoring,
            pollingInterval: pollingInterval,
            averageProcessingTime: 0.0, // Will be provided by PerformanceMonitor
            memoryUsage: 0, // Will be provided by StorageService
            cacheHitRate: 0.0 // Will be provided by CacheManager
        )
    }

    // MARK: - Private Methods

    @discardableResult
    private func checkClipboard(force: Bool = false) async -> ClipboardItem? {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount

        guard force || changeCount != lastChangeCount else { return nil }
        lastChangeCount = changeCount

        do {
            // Check for privacy compliance (macOS Sequoia)
            let isCompliant = await checkPrivacyCompliance(pasteboard)
            if !isCompliant {
                return nil
            }

            // Process clipboard content
            guard let item = await processClipboardContent(pasteboard) else { return nil }

            // Check for duplicates
            if !force && item.metadata.hash == lastHash {
                return nil
            }
            lastHash = item.metadata.hash

            // Apply security checks
            let secureItem = await applySecurityChecks(item)

            // Store the item
            try await storageService.saveItem(secureItem)

            // Update statistics
            totalItemsProcessed += 1
            lastDetectionTime = Date()

            // Notify subscribers
            itemSubject.send(secureItem)

            return secureItem

        } catch {
            detectionErrors += 1
            let clipboardError = ClipboardError.processingFailed(error)
            errorSubject.send(clipboardError)
            return nil
        }
    }

    private func checkPrivacyCompliance(_ pasteboard: NSPasteboard) async -> Bool {
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

    private func processClipboardContent(_ pasteboard: NSPasteboard) async -> ClipboardItem? {
        guard let types = pasteboard.types, !types.isEmpty else { return nil }

        // Enhanced debug logging to understand what types are present
        print("🔍 Clipboard types found: \(types.map { $0.rawValue })")

        // Check for file URLs specifically
        if types.contains(.fileURL) {
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                let fileURLs = urls.filter { $0.isFileURL }
                print("📁 Found \(fileURLs.count) file URLs: \(fileURLs.map { $0.lastPathComponent })")
            }
        }

        // Check what string content we have
        if types.contains(.string) {
            if let stringContent = pasteboard.string(forType: .string) {
                let preview = stringContent.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)
                print("📄 String content preview: \"\(preview)\"")
            }
        }

        let content: ClipboardContent?

        // Priority order for content detection - files MUST come first before images
        if types.contains(.fileURL) {
            print("📁 Processing as file content (highest priority)")
            content = await processFileContent(pasteboard)
            // If file processing fails, don't fall back to image processing for file types
            if content == nil {
                print("❌ File processing failed, but not falling back to image processing")
                return nil
            }
        } else if types.contains(.URL) {
            print("🔗 Processing as URL content")
            content = await processURLContent(pasteboard)
        } else if types.contains(.png) || types.contains(.tiff) {
            print("🖼️ Processing as image content")
            content = await processImageContent(pasteboard)
        } else if types.contains(.rtf) {
            print("📝 Processing as rich text content")
            content = await processRichTextContent(pasteboard)
        } else if types.contains(.string) {
            print("📄 Processing as text content")
            content = await processTextContent(pasteboard)
        } else if types.contains(.color) {
            print("🎨 Processing as color content")
            content = await processColorContent(pasteboard)
        } else {
            print("❓ Processing as generic content")
            content = await processGenericContent(pasteboard, types: types)
        }

        if let clipboardContent = content {
            print("✅ Content classified as: \(clipboardContent.contentType)")
        } else {
            print("❌ Failed to process clipboard content")
        }

        guard let clipboardContent = content else { return nil }

        let metadata = ItemMetadata.generate(for: clipboardContent)
        let source = await getCurrentApplicationInfo()

        return ClipboardItem(
            content: clipboardContent,
            metadata: metadata,
            source: source
        )
    }

    private func processTextContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        guard let text = pasteboard.string(forType: .string) else { return nil }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        print("📄 Text content: \"\(trimmedText.prefix(50))...\"")

        // Check if it's a URL first - prioritize URL detection
        print("🔍 Checking if text is URL: \(trimmedText.isValidURL)")
        if trimmedText.isValidURL, let url = URL(string: trimmedText) {
            print("🔗 Converting text to link content for URL: \(url)")
            let (title, description, favicon, preview) = await fetchURLMetadata(url)
            return .link(LinkContent(
                url: url,
                title: title,
                description: description,
                faviconData: favicon,
                previewImageData: preview
            ))
        }

        let textContent = TextContent(
            plainText: text,
            language: await detectLanguage(text),
            isEmail: text.isValidEmail,
            isPhoneNumber: text.isValidPhoneNumber,
            isURL: text.isValidURL
        )

        // Check if it's actually code
        if let detectedLanguage = await detectProgrammingLanguage(text) {
            return .code(CodeContent(code: text, language: detectedLanguage))
        }

        return .text(textContent)
    }

    private func processRichTextContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        guard let rtfData = pasteboard.data(forType: .rtf) else { return nil }

        var htmlString: String?
        var attributedStringData: Data?
        var plainTextFallback = ""

        // Try to get HTML representation
        if let html = pasteboard.string(forType: .html) {
            htmlString = html
        }

        // Get attributed string data
        if let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            attributedStringData = try? NSKeyedArchiver.archivedData(withRootObject: attrString, requiringSecureCoding: true)
            plainTextFallback = attrString.string
        }

        // Fallback to plain text
        if plainTextFallback.isEmpty {
            plainTextFallback = pasteboard.string(forType: .string) ?? "Rich text content"
        }

        return .richText(RichTextContent(
            rtfData: rtfData,
            htmlString: htmlString,
            attributedStringData: attributedStringData ?? Data(),
            plainTextFallback: plainTextFallback
        ))
    }

    private func processImageContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        guard let image = NSImage(pasteboard: pasteboard) else { return nil }

        // Determine the best representation
        var imageData: Data?
        var format: ImageFormat = .png

        if let pngData = pasteboard.data(forType: .png) {
            imageData = pngData
            format = .png
        } else if let tiffData = image.tiffRepresentation {
            imageData = tiffData
            format = .tiff
        }

        guard let data = imageData else { return nil }

        // Generate thumbnail
        let thumbnailPath = await generateThumbnail(for: image)

        // Extract color palette
        let colorPalette = await extractColorPalette(from: image)

        // Check for transparency
        let hasTransparency = await checkTransparency(image: image)

        return .image(ImageContent(
            data: data,
            format: format,
            dimensions: image.size,
            thumbnailPath: thumbnailPath,
            colorPalette: colorPalette,
            hasTransparency: hasTransparency
        ))
    }

    private func processFileContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        print("📁 Entering processFileContent...")

        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            print("❌ No URLs found in pasteboard")
            return nil
        }

        print("📁 Found \(urls.count) URLs: \(urls.map { $0.absoluteString })")

        let fileURLs = urls.filter { $0.isFileURL }
        print("📁 Filtered to \(fileURLs.count) file URLs: \(fileURLs.map { $0.path })")

        guard !fileURLs.isEmpty else {
            print("❌ No file URLs after filtering")
            return nil
        }

        let totalSize = fileURLs.reduce(Int64(0)) { sum, url in
            do {
                let resources = try url.resourceValues(forKeys: [.fileSizeKey])
                let size = Int64(resources.fileSize ?? 0)
                print("📁 File \(url.lastPathComponent) size: \(size) bytes")
                return sum + size
            } catch {
                print("❌ Failed to get size for \(url.lastPathComponent): \(error)")
                return sum
            }
        }

        let fileName = fileURLs.count == 1 ?
            fileURLs.first!.lastPathComponent :
            "\(fileURLs.count) files"

        let fileType = fileURLs.first?.pathExtension ?? "mixed"
        let isDirectory = fileURLs.allSatisfy { url in
            let result = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            print("📁 \(url.lastPathComponent) isDirectory: \(result)")
            return result
        }

        print("📁 Creating FileContent - fileName: \(fileName), fileType: \(fileType), totalSize: \(totalSize), isDirectory: \(isDirectory)")

        return .file(FileContent(
            urls: fileURLs,
            fileName: fileName,
            fileSize: totalSize,
            fileType: fileType,
            isDirectory: isDirectory
        ))
    }

    private func processURLContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        guard let urlString = pasteboard.string(forType: .URL),
              let url = URL(string: urlString) else { return nil }

        // Fetch metadata asynchronously
        let (title, description, favicon, preview) = await fetchURLMetadata(url)

        return .link(LinkContent(
            url: url,
            title: title,
            description: description,
            faviconData: favicon,
            previewImageData: preview
        ))
    }

    private func processColorContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        guard let color = NSColor(from: pasteboard) else { return nil }
        return .color(ColorContent(nsColor: color))
    }

    private func processGenericContent(_ pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) async -> ClipboardContent? {
        // Handle multiple items
        var items: [ClipboardContent] = []

        for type in types.prefix(5) { // Limit to first 5 types
            if let data = pasteboard.data(forType: type) {
                if type == .string, let text = String(data: data, encoding: .utf8) {
                    items.append(.text(TextContent(plainText: text)))
                }
                // Add more type handling as needed
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

    private func applySecurityChecks(_ item: ClipboardItem) async -> ClipboardItem {
        // Security features removed for v1 - no processing needed
        return item
    }

    private func getCurrentApplicationInfo() async -> ItemSource {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        // Find the frontmost app
        if let frontApp = runningApps.first(where: { $0.isActive }) {
            return ItemSource(
                applicationBundleID: frontApp.bundleIdentifier,
                applicationName: frontApp.localizedName,
                applicationIcon: frontApp.icon?.tiffRepresentation
            )
        }

        return ItemSource()
    }

    // MARK: - Helper Methods

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
            ("swift", ["func ", "var ", "let ", "import ", "class ", "struct "]),
            ("javascript", ["function ", "const ", "let ", "var ", "=> ", "console.log"]),
            ("python", ["def ", "import ", "from ", "class ", "if __name__"]),
            ("java", ["public class", "private ", "public static void main"]),
            ("html", ["<html", "<div", "<span", "<!DOCTYPE"]),
            ("css", ["{", "}", ":", ";", "px", "margin", "padding"]),
            ("json", ["{\"", "\":", "[{", "}]"]),
            ("xml", ["<?xml", "<!", "</"]),
            ("sql", ["SELECT ", "FROM ", "WHERE ", "INSERT ", "UPDATE "])
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

    private func generateThumbnail(for image: NSImage) async -> String {
        // Generate thumbnail and save to cache directory
        // Return path to thumbnail file
        let thumbnailSize = NSSize(width: 200, height: 200)
        let thumbnail = image.resized(to: thumbnailSize)

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let thumbnailDir = cacheDir.appendingPathComponent("ClipFlow/thumbnails", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)
            let thumbnailPath = thumbnailDir.appendingPathComponent("\(UUID().uuidString).png")

            if let tiffData = thumbnail?.tiffRepresentation,
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

    private func extractColorPalette(from image: NSImage) async -> [String] {
        // Simple color extraction - in a real implementation,
        // you would use more sophisticated algorithms
        return []
    }

    private func checkTransparency(image: NSImage) async -> Bool {
        // Check if image has alpha channel
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        let alphaInfo = cgImage.alphaInfo
        return alphaInfo == .first || alphaInfo == .last ||
               alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
    }

    private func fetchURLMetadata(_ url: URL) async -> (title: String?, description: String?, favicon: Data?, preview: Data?) {
        // This would fetch metadata from the URL
        // For now, return nil values
        return (nil, nil, nil, nil)
    }
}

// MARK: - Supporting Types





// MARK: - NSImage Extensions

private extension NSImage {
    func resized(to size: NSSize) -> NSImage? {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }

        draw(in: NSRect(origin: .zero, size: size),
             from: NSRect(origin: .zero, size: self.size),
             operation: .sourceOver,
             fraction: 1.0)

        return newImage
    }
}