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
        // Insert at beginning and remove duplicates
        items.removeAll { $0.id == item.id }
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
                    items = history
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

    func addTags(to item: ClipboardItem, tags: Set<String>) {
        Task {
            do {
                try await clipboardService.addTags(tags, to: item.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func assignTags(to item: ClipboardItem) {
        // This will open the tag assignment UI
        // For now, we'll just log it - the actual UI integration will come later
        print("🏷️ Opening tag assignment for item: \(item.id)")
        
        // TODO: Present TagAssignmentView as a sheet or popover
        // This requires integration with the main view controller
    }

    // MARK: - Search and Filtering

    func filteredItems(for searchText: String) -> [ClipboardItem] {
        guard !searchText.isEmpty else { return items }

        return items.filter { item in
            // Search in content
            let contentMatch = item.content.displayText.localizedCaseInsensitiveContains(searchText)

            // Search in tags
            let tagMatch = item.tags.contains { tag in
                tag.localizedCaseInsensitiveContains(searchText)
            }

            // Search in source application
            let appMatch = item.source.applicationName?.localizedCaseInsensitiveContains(searchText) ?? false

            return contentMatch || tagMatch || appMatch
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
            let source = ItemSource()

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