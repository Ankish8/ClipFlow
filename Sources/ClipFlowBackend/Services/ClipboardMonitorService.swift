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
            NSLog("🚀 About to call processClipboardContent")
            guard let item = await processClipboardContent(pasteboard) else {
                NSLog("❌ processClipboardContent returned nil")
                return nil
            }
            NSLog("✅ processClipboardContent returned successfully with item: \(item.content.contentType)")

            // Check for duplicates
            NSLog("🔍 Checking duplicates: force=\(force), lastHash=\(lastHash), newHash=\(item.metadata.hash)")
            if !force && item.metadata.hash == lastHash {
                NSLog("❌ Duplicate detected - skipping item")
                return nil
            }
            lastHash = item.metadata.hash
            NSLog("✅ Duplicate check passed")

            // Apply security checks
            NSLog("🔒 About to apply security checks")
            let secureItem = await applySecurityChecks(item)
            NSLog("✅ Security checks completed")

            // Store the item
            NSLog("💾 About to save item to storage")
            try await storageService.saveItem(secureItem)
            NSLog("💾 Successfully saved item to storage: \(secureItem.content.contentType)")

            // Update statistics
            totalItemsProcessed += 1
            lastDetectionTime = Date()

            // Notify subscribers
            itemSubject.send(secureItem)
            NSLog("📢 Notified subscribers about new item")

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
        NSLog("🔍 Clipboard types found: \(types.map { $0.rawValue })")
        NSLog("🔍 .string type resolves to: \(NSPasteboard.PasteboardType.string.rawValue)")
        NSLog("🔍 .URL type resolves to: \(NSPasteboard.PasteboardType.URL.rawValue)")
        NSLog("🔍 types.contains(.string): \(types.contains(.string))")
        NSLog("🔍 types.contains(.URL): \(types.contains(.URL))")

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
                NSLog("📄 String content preview: \"\(preview)\"")

                // Test URL detection
                let isURL = stringContent.isValidURL
                NSLog("🔗 URL detection result: \(isURL) for content: \(preview)")
            }
        }

        let content: ClipboardContent?
        NSLog("🚀 About to enter content processing branches")

        // FIXED priority order: Check native URLs first, then intelligent file/image detection, then text with URL detection
        NSLog("🔍 Checking .URL: \(types.contains(.URL))")
        if types.contains(.URL) {
            print("🔗 Processing as native URL content")
            content = await processURLContent(pasteboard)
        } else if types.contains(.fileURL) && !(types.contains(.png) || types.contains(.tiff)) {
            // Only process as file if it's a file WITHOUT image types (prevents duplication)
            print("📁 Processing as pure file content")
            content = await processFileContent(pasteboard)
        } else if types.contains(.png) || types.contains(.tiff) {
            // Handle images - check if they're files or pure images, but process only ONCE
            NSLog("🔍 Checking .png/.tiff: \(types.contains(.png)) / \(types.contains(.tiff))")
            if types.contains(.fileURL) {
                print("📁 Image file detected - processing as file only")
                content = await processFileContent(pasteboard)
            } else {
                print("🖼️ Processing as pure image content")
                content = await processImageContent(pasteboard)
            }
        } else if types.contains(.rtf) {
            NSLog("🔍 Checking .rtf: \(types.contains(.rtf))")
            print("📝 Processing as rich text content")
            content = await processRichTextContent(pasteboard)
        } else if types.contains(.string) {
            NSLog("🔍 Checking .string: \(types.contains(.string))")
            NSLog("📄 Processing as text content - about to call processTextContent")
            content = await processTextContent(pasteboard) // This will detect URLs in text
            NSLog("📄 Returned from processTextContent: \(content != nil ? "SUCCESS" : "NIL")")
        } else if types.contains(.color) {
            NSLog("🔍 Checking .color: \(types.contains(.color))")
            print("🎨 Processing as color content")
            content = await processColorContent(pasteboard)
        } else {
            print("❓ Processing as generic content")
            content = await processGenericContent(pasteboard, types: types)
        }

        NSLog("🔍 After content processing, content is: \(content != nil ? "NOT NIL" : "NIL")")
        if let clipboardContent = content {
            NSLog("✅ Content classified as: \(clipboardContent.contentType)")
        } else {
            NSLog("❌ Failed to process clipboard content")
            return nil
        }

        guard let clipboardContent = content else {
            NSLog("❌ Content guard failed - returning nil")
            return nil
        }

        NSLog("🚀 About to generate metadata for content")

        let metadata = ItemMetadata.generate(for: clipboardContent)
        NSLog("✅ Generated metadata successfully")

        let source = await getCurrentApplicationInfo()
        NSLog("✅ Got application info")

        let finalItem = ClipboardItem(
            content: clipboardContent,
            metadata: metadata,
            source: source
        )
        NSLog("✅ Created final ClipboardItem successfully")

        return finalItem
    }

    private func processTextContent(_ pasteboard: NSPasteboard) async -> ClipboardContent? {
        NSLog("🚀 ENTERED processTextContent method")
        guard let text = pasteboard.string(forType: .string) else {
            print("❌ No string content in pasteboard")
            return nil
        }
        NSLog("✅ Got text from pasteboard: \(text.prefix(50))")

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        print("📄 Text content: \"\(trimmedText.prefix(50))\"")

        // Explicit test of URL validation
        let urlTest = trimmedText.isValidURL
        print("🔍 URL validation result for '\(trimmedText)': \(urlTest)")

        // Manual URL check for debugging
        let hasHttps = trimmedText.lowercased().hasPrefix("https://")
        let hasHttp = trimmedText.lowercased().hasPrefix("http://")
        let canCreateURL = URL(string: trimmedText) != nil
        print("📊 URL Debug - hasHttps: \(hasHttps), hasHttp: \(hasHttp), canCreateURL: \(canCreateURL)")

        // Check if it's a URL first - prioritize URL detection
        NSLog("🔍 About to check URL conversion: isValidURL=\(trimmedText.isValidURL)")
        if trimmedText.isValidURL, let url = URL(string: trimmedText) {
            NSLog("🔗 SUCCESS: Converting text to link content for URL: \(url)")
            // TEMPORARY FIX: Skip metadata fetching to avoid hanging
            NSLog("🔄 Skipping metadata fetch for debugging")
            return .link(LinkContent(
                url: url,
                title: url.absoluteString,
                description: nil,
                faviconData: nil,
                previewImageData: nil
            ))
        } else {
            NSLog("❌ URL validation failed - treating as plain text")
        }

        let textContent = TextContent(
            plainText: text,
            language: "en", // TEMPORARY FIX: Skip language detection to avoid hanging
            isEmail: text.isValidEmail,
            isPhoneNumber: text.isValidPhoneNumber,
            isURL: text.isValidURL
        )

        // TEMPORARY FIX: Skip programming language detection to avoid hanging
        // if let detectedLanguage = await detectProgrammingLanguage(text) {
        //     return .code(CodeContent(code: text, language: detectedLanguage))
        // }

        let result: ClipboardContent = .text(textContent)
        NSLog("📤 processTextContent returning: \(result)")
        return result
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