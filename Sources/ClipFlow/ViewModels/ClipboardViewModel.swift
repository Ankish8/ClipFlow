import SwiftUI
import Combine
import AppKit
import ClipFlowCore
import ClipFlowAPI
import ClipFlowBackend

@MainActor
class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statistics: ClipboardStatistics?

    private var cancellables = Set<AnyCancellable>()
    private let clipboardService = ClipboardService.shared

    // Drag protection
    private var isDragInProgress = false
    private var itemsBackup: [ClipboardItem] = []

    func initialize() {
        print("🚀 ViewModel initializing...")
        setupSubscriptions()
        loadInitialData()

        // Add simple clipboard monitoring as backup
        startSimpleClipboardMonitoring()

        // Subscribe to drag notifications for data protection
        setupDragProtection()
    }

    private func setupSubscriptions() {
        // Subscribe to real-time clipboard updates
        clipboardService.itemUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newItem in
                self?.handleNewItem(newItem)
            }
            .store(in: &cancellables)

        // Subscribe to errors
        clipboardService.errors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error.localizedDescription
            }
            .store(in: &cancellables)

        // Subscribe to status updates
        clipboardService.statusUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleStatusUpdate(status)
            }
            .store(in: &cancellables)
    }

    private func handleNewItem(_ item: ClipboardItem) {
        // Remove duplicates by ID or hash, but KEEP the new item (it might have better classification)
        items.removeAll { existingItem in
            existingItem.id == item.id || existingItem.metadata.hash == item.metadata.hash
        }
        // Insert the NEW item at the beginning (it has the latest/correct classification)
        items.insert(item, at: 0)

        // Limit to reasonable number for performance
        if items.count > 1000 {
            items = Array(items.prefix(1000))
        }
    }

    private func handleStatusUpdate(_ status: MonitorStatus) {
        switch status {
        case .monitoring:
            isLoading = false
            errorMessage = nil
        case .error(let error):
            errorMessage = error.localizedDescription
            isLoading = false
        case .stopped, .paused:
            isLoading = true
        }
    }

    private func loadInitialData() {
        Task {
            do {
                isLoading = true
                let history = try await clipboardService.getHistory(
                    offset: 0,
                    limit: 100,
                    filter: nil
                )

                // Only update items if not currently dragging
                if !isDragInProgress {
                    // Merge history with existing items, preferring existing (newer/correct) items
                    var mergedItems: [ClipboardItem] = items
                    for historyItem in history {
                        // Only add if not already present (by ID or hash)
                        let isDuplicate = mergedItems.contains { existing in
                            existing.id == historyItem.id || existing.metadata.hash == historyItem.metadata.hash
                        }
                        if !isDuplicate {
                            mergedItems.append(historyItem)
                        }
                    }
                    items = mergedItems
                } else {
                    print("🛡️ Skipping data update during drag operation")
                }

                // Load statistics
                statistics = await clipboardService.getStatistics()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - User Actions

    func togglePin(for item: ClipboardItem) {
        Task {
            do {
                try await clipboardService.togglePin(itemId: item.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleFavorite(for item: ClipboardItem) {
        Task {
            do {
                try await clipboardService.toggleFavorite(itemId: item.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteItem(_ item: ClipboardItem) {
        Task {
            do {
                try await clipboardService.deleteItems(ids: [item.id])
                items.removeAll { $0.id == item.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func pasteItem(_ item: ClipboardItem, transform: TransformAction? = nil) {
        Task {
            do {
                try await clipboardService.paste(item, transform: transform)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }


    // MARK: - Search and Filtering

    func filteredItems(for searchText: String) -> [ClipboardItem] {
        guard !searchText.isEmpty else { return items }

        return items.filter { item in
            // Search in content
            let contentMatch = item.content.displayText.localizedCaseInsensitiveContains(searchText)

            // Search in source application
            let appMatch = item.source.applicationName?.localizedCaseInsensitiveContains(searchText) ?? false

            return contentMatch || appMatch
        }
    }

    func performFullTextSearch(_ query: String) {
        guard !query.isEmpty else {
            loadInitialData()
            return
        }

        Task {
            do {
                isLoading = true
                let results = try await clipboardService.search(
                    query: query,
                    scope: .all,
                    limit: 100
                )
                items = results
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Data Management

    func refreshData() {
        if !isDragInProgress {
            loadInitialData()
        } else {
            print("🛡️ Skipping refresh during drag operation")
        }
    }

    func clearHistory() {
        // Don't clear during drag
        guard !isDragInProgress else {
            print("🛡️ Preventing clear history during drag operation")
            return
        }

        Task {
            do {
                try await clipboardService.clearHistory(olderThan: nil)
                items.removeAll()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore() {
        Task {
            do {
                let moreItems = try await clipboardService.getHistory(
                    offset: items.count,
                    limit: 50,
                    filter: nil
                )
                items.append(contentsOf: moreItems)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Simple Clipboard Monitoring

    private var simpleTimer: Timer?
    private var lastChangeCount = 0

    private func startSimpleClipboardMonitoring() {
        print("📋 Starting simple clipboard monitoring...")

        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount

        simpleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSimpleClipboard()
            }
        }
    }

    private func checkSimpleClipboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        print("📝 Clipboard changed! Change count: \(currentChangeCount)")

        // Check available types
        let types = pasteboard.types ?? []
        print("📋 Available types: \(types)")

        var clipboardContent: ClipboardContent?

        // Priority order: Images -> Files -> URLs -> Rich Text -> Plain Text
        if types.contains(.png) || types.contains(.tiff) {
            clipboardContent = processImageFromPasteboard(pasteboard)
        } else if types.contains(.fileURL) {
            clipboardContent = processFileFromPasteboard(pasteboard)
        } else if types.contains(.URL) {
            clipboardContent = processURLFromPasteboard(pasteboard)
        } else if types.contains(.rtf) {
            clipboardContent = processRichTextFromPasteboard(pasteboard)
        } else if types.contains(.string) {
            clipboardContent = processTextFromPasteboard(pasteboard)
        }

        if let content = clipboardContent {
            let metadata = ItemMetadata.generate(for: content)
            let source = getCurrentApplicationInfo()

            let item = ClipboardItem(
                content: content,
                metadata: metadata,
                source: source
            )

            // Add to list (already on main actor)
            self.items.removeAll { $0.metadata.hash == item.metadata.hash }
            self.items.insert(item, at: 0)

            if self.items.count > 100 {
                self.items = Array(self.items.prefix(100))
            }

            print("✅ Added \(content.contentType) item to list. Total items: \(self.items.count)")
        } else {
            print("❌ Could not process clipboard content")
        }
    }

    // MARK: - Content Processing Methods

    private func processTextFromPasteboard(_ pasteboard: NSPasteboard) -> ClipboardContent? {
        guard let text = pasteboard.string(forType: .string) else { return nil }
        print("📄 Processing text: \(text.prefix(50))...")

        // Check if it's a URL first (same logic as backend)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isValidURL {
            // Clean the text by removing newlines (for multi-line URLs)
            let cleanedText = trimmedText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined()

            if let url = URL(string: cleanedText) {
                print("🔗 Simple monitor: Detected URL, creating link content")
                return .link(LinkContent(url: url, title: url.absoluteString))
            }
        }

        return .text(TextContent(plainText: text))
    }

    private func processImageFromPasteboard(_ pasteboard: NSPasteboard) -> ClipboardContent? {
        guard let image = NSImage(pasteboard: pasteboard) else { return nil }

        var imageData: Data?
        var format: ImageFormat = .png

        // Try to get PNG data first
        if let pngData = pasteboard.data(forType: .png) {
            imageData = pngData
            format = .png
            print("🖼️ Processing PNG image: \(image.size)")
        } else if let tiffData = image.tiffRepresentation {
            imageData = tiffData
            format = .tiff
            print("🖼️ Processing TIFF image: \(image.size)")
        }

        guard let data = imageData else { return nil }

        return .image(ImageContent(
            data: data,
            format: format,
            dimensions: image.size,
            thumbnailPath: "", // We'll generate this later if needed
            colorPalette: [],
            hasTransparency: false
        ))
    }

    private func processFileFromPasteboard(_ pasteboard: NSPasteboard) -> ClipboardContent? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return nil
        }

        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return nil }

        print("📁 Processing \(fileURLs.count) file(s)")

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

        return .file(FileContent(
            urls: fileURLs,
            fileName: fileName,
            fileSize: totalSize,
            fileType: fileType,
            isDirectory: false
        ))
    }

    private func processURLFromPasteboard(_ pasteboard: NSPasteboard) -> ClipboardContent? {
        guard let urlString = pasteboard.string(forType: .URL),
              let url = URL(string: urlString) else { return nil }

        print("🔗 Processing URL: \(url.absoluteString)")

        return .link(LinkContent(url: url))
    }

    private func processRichTextFromPasteboard(_ pasteboard: NSPasteboard) -> ClipboardContent? {
        guard let rtfData = pasteboard.data(forType: .rtf) else { return nil }

        var plainTextFallback = ""
        var attributedStringData = Data()

        // Get plain text fallback
        if let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            plainTextFallback = attrString.string
            attributedStringData = (try? NSKeyedArchiver.archivedData(withRootObject: attrString, requiringSecureCoding: true)) ?? Data()
        }

        // Fallback to plain text if needed
        if plainTextFallback.isEmpty {
            plainTextFallback = pasteboard.string(forType: .string) ?? "Rich text content"
        }

        print("📝 Processing rich text: \(plainTextFallback.prefix(50))...")

        return .richText(RichTextContent(
            rtfData: rtfData,
            htmlString: pasteboard.string(forType: .html),
            attributedStringData: attributedStringData,
            plainTextFallback: plainTextFallback
        ))
    }

    // MARK: - App Source Detection

    /// Captures information about the frontmost application (excluding ClipFlow itself)
    /// Mirrors logic from ClipboardMonitorService.getCurrentApplicationInfo()
    private func getCurrentApplicationInfo() -> ItemSource {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        // Get ClipFlow's bundle ID to exclude it
        let clipFlowBundleID = Bundle.main.bundleIdentifier

        // Strategy 1: Find the frontmost app (excluding ClipFlow itself)
        var targetApp: NSRunningApplication? = runningApps.first(where: { app in
            app.isActive && app.bundleIdentifier != clipFlowBundleID
        })

        // Strategy 2: If no active non-ClipFlow app, find the frontmost window's app
        if targetApp == nil {
            if let frontWindow = workspace.frontmostApplication,
               frontWindow.bundleIdentifier != clipFlowBundleID {
                targetApp = frontWindow
                NSLog("📱 Using frontmost application fallback")
            }
        }

        // Strategy 3: Use any running app except ClipFlow as last resort
        if targetApp == nil {
            targetApp = runningApps.first(where: { app in
                !app.isTerminated &&
                app.bundleIdentifier != clipFlowBundleID &&
                app.bundleIdentifier != "com.apple.dock" &&
                app.bundleIdentifier != "com.apple.WindowManager"
            })
            if targetApp != nil {
                NSLog("📱 Using any running app fallback")
            }
        }

        // If we found an app, compress and return its info
        if let frontApp = targetApp {
            // Compress icon to reasonable size (TIFF can be huge for retina icons)
            var iconData: Data? = nil
            if let icon = frontApp.icon {
                // Resize icon to standard 128x128 and convert to PNG for smaller size
                let targetSize = NSSize(width: 128, height: 128)
                let resizedIcon = NSImage(size: targetSize)
                resizedIcon.lockFocus()
                icon.draw(in: NSRect(origin: .zero, size: targetSize),
                         from: NSRect(origin: .zero, size: icon.size),
                         operation: .sourceOver,
                         fraction: 1.0)
                resizedIcon.unlockFocus()

                // Convert to PNG for much smaller file size
                if let tiffData = resizedIcon.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    iconData = pngData
                    NSLog("🎨 Compressed icon: \(frontApp.localizedName ?? "Unknown") from \(frontApp.icon?.tiffRepresentation?.count ?? 0) to \(pngData.count) bytes")
                }
            }

            let source = ItemSource(
                applicationBundleID: frontApp.bundleIdentifier,
                applicationName: frontApp.localizedName,
                applicationIcon: iconData
            )

            NSLog("📱 Captured source app: \(source.applicationName ?? "Unknown") (\(source.applicationBundleID ?? "nil"))")
            return source
        }

        // Absolute fallback: Return System as the source with a generic icon
        NSLog("⚠️ No valid application found - using System fallback")

        // Create a generic system icon
        var systemIconData: Data? = nil
        let systemIcon = NSWorkspace.shared.icon(forFile: "/System")
        let targetSize = NSSize(width: 128, height: 128)
        let resizedIcon = NSImage(size: targetSize)
        resizedIcon.lockFocus()
        systemIcon.draw(in: NSRect(origin: .zero, size: targetSize),
                       from: NSRect(origin: .zero, size: systemIcon.size),
                       operation: .sourceOver,
                       fraction: 1.0)
        resizedIcon.unlockFocus()

        if let tiffData = resizedIcon.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            systemIconData = pngData
        }

        return ItemSource(
            applicationBundleID: "com.apple.system",
            applicationName: "System",
            applicationIcon: systemIconData
        )
    }

    func cleanup() {
        simpleTimer?.invalidate()
        simpleTimer = nil
    }

    // MARK: - Drag Protection

    private func setupDragProtection() {
        // Subscribe to start dragging notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("startDragging"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDragStart()
            }
        }

        // Subscribe to stop dragging notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("stopDragging"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDragEnd()
            }
        }
    }

    private func handleDragStart() {
        print("🛡️ Drag started - backing up \(items.count) items")
        isDragInProgress = true
        itemsBackup = items // Backup current items
    }

    private func handleDragEnd() {
        print("🛡️ Drag ended - checking data integrity")
        isDragInProgress = false

        // If items were cleared during drag, restore from backup
        if items.isEmpty && !itemsBackup.isEmpty {
            print("🔧 Data was lost during drag - restoring \(itemsBackup.count) items")
            items = itemsBackup
        }

        // Clear backup after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.itemsBackup.removeAll()
        }
    }
}