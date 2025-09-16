import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers
import ClipFlowCore

// MARK: - Clipboard Monitor Service

public actor ClipboardMonitorService {
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
    private let securityService: SecurityService
    private let performanceMonitor: PerformanceMonitor

    // Statistics
    private var totalItemsProcessed: Int = 0
    private var detectionErrors: Int = 0
    private var lastDetectionTime: Date?

    // MARK: - Public Publishers

    public nonisolated var itemUpdates: AnyPublisher<ClipboardItem, Never> {
        itemSubject.eraseToAnyPublisher()
    }

    public nonisolated var errors: AnyPublisher<ClipboardError, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    public nonisolated var status: AnyPublisher<MonitorStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    public init(
        storageService: StorageService,
        securityService: SecurityService,
        performanceMonitor: PerformanceMonitor = PerformanceMonitor.shared
    ) {
        self.storageService = storageService
        self.securityService = securityService
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

        await MainActor.run {
            timer?.invalidate()
            timer = nil
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
            pollingInterval: pollingInterval
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
            if !await checkPrivacyCompliance(pasteboard) {
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

        let content: ClipboardContent?

        // Priority order for content detection
        if types.contains(.png) || types.contains(.jpeg) || types.contains(.tiff) {
            content = await processImageContent(pasteboard)
        } else if types.contains(.fileURL) {
            content = await processFileContent(pasteboard)
        } else if types.contains(.URL) {
            content = await processURLContent(pasteboard)
        } else if types.contains(.rtf) {
            content = await processRichTextContent(pasteboard)
        } else if types.contains(.string) {
            content = await processTextContent(pasteboard)
        } else if types.contains(.color) {
            content = await processColorContent(pasteboard)
        } else {
            content = await processGenericContent(pasteboard, types: types)
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
        } else if let jpegData = pasteboard.data(forType: .jpeg) {
            imageData = jpegData
            format = .jpeg
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
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return nil
        }

        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return nil }

        let totalSize = fileURLs.reduce(0) { sum, url in
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
        guard let color = NSColor(pasteboard: pasteboard) else { return nil }
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
        var secureItem = item

        // Detect sensitive content
        let isSensitive = SecurityMetadata.detectSensitive(from: item.content)

        // Apply encryption if needed
        let shouldEncrypt = isSensitive || await securityService.shouldEncrypt(item)

        if shouldEncrypt {
            // Encrypt the item (implementation would depend on SecurityService)
            // For now, just mark it as sensitive
            secureItem.security = SecurityMetadata(
                isEncrypted: false, // Would be true after encryption
                isSensitive: isSensitive,
                accessControl: isSensitive ? .private : .public
            )
        }

        return secureItem
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
}

public struct ClipboardStatistics {
    public let totalItemsProcessed: Int
    public let detectionErrors: Int
    public let lastDetectionTime: Date?
    public let isMonitoring: Bool
    public let pollingInterval: TimeInterval

    public init(
        totalItemsProcessed: Int,
        detectionErrors: Int,
        lastDetectionTime: Date?,
        isMonitoring: Bool,
        pollingInterval: TimeInterval
    ) {
        self.totalItemsProcessed = totalItemsProcessed
        self.detectionErrors = detectionErrors
        self.lastDetectionTime = lastDetectionTime
        self.isMonitoring = isMonitoring
        self.pollingInterval = pollingInterval
    }
}

// MARK: - String Extensions

private extension String {
    var isValidEmail: Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return range(of: emailRegex, options: .regularExpression) != nil
    }

    var isValidPhoneNumber: Bool {
        let phoneRegex = #"^[\+]?[1-9][\d]{0,15}$"#
        let cleaned = components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return cleaned.range(of: phoneRegex, options: .regularExpression) != nil
    }

    var isValidURL: Bool {
        guard let url = URL(string: self) else { return false }
        return url.scheme != nil && !url.scheme!.isEmpty
    }
}

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