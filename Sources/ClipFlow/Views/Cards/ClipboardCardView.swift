import SwiftUI
import ClipFlowCore
import UniformTypeIdentifiers

struct ClipboardCardView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let viewModel: ClipboardViewModel
    @State private var isHovering = false
    @State private var hoveredButton: String? = nil
    @State private var isDeleting = false
    @State private var cachedImagePath: String? = nil
    @State private var showCopyFeedback = false
    @State private var accentColor: Color? = nil
    @State private var showTooltip = false

    private var contentTypeInfo: ContentTypeInfo {
        ContentTypeInfo.from(item.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header with type badge and index
            cardHeader

            // Content preview
            contentPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Metadata footer
            cardFooter
        }
        .frame(width: cardWidth, height: 250)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isDeleting ? 0.8 : 1.0)
        .scaleEffect(showCopyFeedback ? 0.95 : 1.0)
        .offset(y: isHovering ? -1 : 0) // transform: translateY(-1px)
        .offset(y: isDeleting ? -20 : 0)
        .opacity(isDeleting ? 0 : 1)
        .animation(.easeInOut(duration: 0.15), value: showCopyFeedback)
        .shadow(
            color: colorScheme == .light ?
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: isHovering ? 0.05 : 0.0) : // rgba(0, 0, 0, 0.05)
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: isHovering ? 0.3 : 0.0),
            radius: isHovering ? 6 : 0,
            x: 0,
            y: isHovering ? 4 : 0
        )
        .shadow(
            color: colorScheme == .light ?
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: isHovering ? 0.08 : 0.0) : // rgba(0, 0, 0, 0.08)
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: isHovering ? 0.2 : 0.0),
            radius: isHovering ? 3 : 0,
            x: 0,
            y: isHovering ? 1 : 0
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.easeInOut(duration: 0.3), value: isDeleting)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onDrag {
            provideDragData()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { _ in
                    NotificationCenter.default.post(name: .startDragging, object: nil)
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .stopDragging, object: nil)
                    }
                }
        )
        .onTapGesture(count: 2) {
            // Double-click to paste and hide overlay
            pasteAndHideOverlay()
        }
        .overlay(alignment: .bottomTrailing) {
            if isHovering && !isDeleting {
                quickActionButtons
                    .contentShape(Rectangle())
                    .padding(.bottom, 44) // Position above footer (footer is ~40px + spacing)
                    .padding(.trailing, 8) // Add right margin
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .onHover { hovering in
                        // Keep the card hover state active when hovering over buttons
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isHovering = hovering
                        }
                    }
            }
        }
        .onAppear {
            // Create temporary file for images asynchronously to avoid blocking main thread during drag
            if case .image(let imageContent) = item.content {
                Task.detached(priority: .utility) {
                    if let tempPath = await createTemporaryImageFileAsync(from: imageContent) {
                        await MainActor.run {
                            cachedImagePath = tempPath
                        }
                    }
                }
            }

            // Extract dominant color from app icon for card theming
            Task {
                await extractAccentColor()
            }
        }
    }

    private var cardWidth: CGFloat {
        return 235  // Uniform width for all card types
    }

    @Environment(\.colorScheme) var colorScheme

    private var cardBackground: some View {
        ZStack {
            // Strong card background like Paste app
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .light ?
                    Color(.sRGB, red: 1.0, green: 1.0, blue: 1.0, opacity: 0.95) : // Much more opaque
                    Color(.sRGB, red: 0.12, green: 0.12, blue: 0.12, opacity: 0.95)  // Strong dark cards
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.thinMaterial) // Subtle blur behind
                )

            // Strong border for clear definition
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .light ?
                    Color(.sRGB, red: 0.85, green: 0.87, blue: 0.9, opacity: 1.0) : // Solid border
                    Color(.sRGB, red: 0.3, green: 0.3, blue: 0.3, opacity: 1.0),
                    lineWidth: 1
                )

            // Subtle colored accent border (inner border)
            if let accentColor = accentColor {
                RoundedRectangle(cornerRadius: 11.5)
                    .stroke(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.20),
                                accentColor.opacity(0.12),
                                accentColor.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .padding(0.5) // Inset slightly from outer border
            }
        }
        .shadow(
            color: colorScheme == .light ?
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.12) : // Much stronger shadow
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.4),
            radius: 8,
            x: 0,
            y: 4
        )
        .shadow(
            color: colorScheme == .light ?
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.08) : // Secondary shadow
                Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.2),
            radius: 3,
            x: 0,
            y: 2
        )
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Subtle content type badge
                Text(contentTypeInfo.name.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(contentTypeInfo.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(contentTypeInfo.color.opacity(0.08))
                    )

                Spacer()

                // Source app icon badge
                ZStack(alignment: .topTrailing) {
                    appIconBadge

                    // Custom tooltip overlay
                    if showTooltip, let appName = item.source.applicationName {
                        Text(appName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.85))
                            )
                            .offset(x: 0, y: -30)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
            }

        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var contentPreview: some View {
        Group {
            switch item.content {
            case .text(let textContent):
                TextPreviewCard(content: textContent)
            case .richText(let richTextContent):
                RichTextPreviewCard(content: richTextContent)
            case .image(let imageContent):
                ImagePreviewCard(content: imageContent)
            case .file(let fileContent):
                FilePreviewCard(content: fileContent)
            case .link(let linkContent):
                LinkPreviewCard(content: linkContent)
            case .code(let codeContent):
                TextPreviewCard(content: TextContent(plainText: codeContent.code))
            case .color(let colorContent):
                ColorPreviewCard(content: colorContent)
            case .snippet(let snippetContent):
                TextPreviewCard(content: TextContent(plainText: snippetContent.content))
            case .multiple(let multiContent):
                MultiPreviewCard(content: multiContent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var cardFooter: some View {
        VStack(spacing: 0) {
            // Exact divider from HTML reference
            Rectangle()
                .fill(colorScheme == .light ?
                    Color(.sRGB, red: 0.886, green: 0.91, blue: 0.941, opacity: 0.5) : // rgba(226, 232, 240, 0.5)
                    Color(.sRGB, red: 0.4, green: 0.4, blue: 0.4, opacity: 0.3)
                )
                .frame(height: 1)

            HStack {
                // Metadata - exact colors from HTML reference
                Text(metadataText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .light ?
                        Color(.sRGB, red: 0.581, green: 0.639, blue: 0.722, opacity: 1.0) : // #94a3b8
                        Color(.sRGB, red: 0.7, green: 0.7, blue: 0.7, opacity: 1.0)
                    )

                Spacer()

                // Timestamp - exact colors from HTML reference
                Text(timeAgoText)
                    .font(.system(size: 11))
                    .foregroundColor(colorScheme == .light ?
                        Color(.sRGB, red: 0.581, green: 0.639, blue: 0.722, opacity: 1.0) : // #94a3b8
                        Color(.sRGB, red: 0.7, green: 0.7, blue: 0.7, opacity: 1.0)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var metadataText: String {
        switch item.content {
        case .text(let content):
            let count = content.plainText.count
            return count == 1 ? "1 character" : "\(count) characters"
        case .richText(let content):
            let count = content.plainTextFallback.count
            return count == 1 ? "1 character" : "\(count) characters"
        case .image(let content):
            return "\(Int(content.dimensions.width)) × \(Int(content.dimensions.height))"
        case .file(let content):
            return formatFileSize(content.fileSize)
        case .link:
            return "Link"
        case .code(let content):
            let count = content.code.count
            return count == 1 ? "1 character" : "\(count) characters"
        case .color:
            return "Color"
        case .snippet(let content):
            let count = content.content.count
            return count == 1 ? "1 character" : "\(count) characters"
        case .multiple(let content):
            return "\(content.items.count) items"
        }
    }

    private var timeAgoText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.timestamps.createdAt, relativeTo: Date())
    }
    
    

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Quick Actions

    private var quickActionButtons: some View {
        HStack(spacing: 6) {
            // Copy action
            quickActionButton(icon: "doc.on.doc", action: copyItem, color: .primary)

            // Delete action
            quickActionButton(icon: "trash", action: deleteItem, color: .primary)

            // Pin/Favorite action
            quickActionButton(icon: item.isFavorite ? "star.fill" : "star", action: pinItem, color: .primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .light ?
                    Color(.sRGB, red: 0.98, green: 0.98, blue: 0.99, opacity: 0.96) :
                    Color(.sRGB, red: 0.15, green: 0.15, blue: 0.16, opacity: 0.96)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(colorScheme == .light ?
                            Color(.sRGB, red: 0.85, green: 0.87, blue: 0.9, opacity: 0.7) :
                            Color(.sRGB, red: 0.35, green: 0.35, blue: 0.36, opacity: 0.7),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: colorScheme == .light ?
                        Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.08) :
                        Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.25),
                    radius: 3,
                    x: 0,
                    y: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func quickActionButton(icon: String, action: @escaping () -> Void, color: Color) -> some View {
        Button(action: {
            // Add haptic feedback
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .light ? color : color.opacity(0.9))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuickActionButtonStyle(color: color, colorScheme: colorScheme))
    }

    // MARK: - Action Methods

    private func copyItem() {
        // Show subtle copy feedback animation
        withAnimation(.easeInOut(duration: 0.15)) {
            showCopyFeedback = true
        }

        // Reset feedback after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.15)) {
                showCopyFeedback = false
            }
        }

        // Perform the paste
        viewModel.pasteItem(item)
    }

    private func pasteAndHideOverlay() {
        // CRITICAL: Hide overlay FIRST to restore focus to original text field
        NotificationCenter.default.post(name: .hideClipboardOverlay, object: nil)

        // Increased delay to 250ms to ensure:
        // 1. Overlay hide animation completes (200ms)
        // 2. Focus restored to previous app/text field via NSWorkspace
        // 3. macOS processes focus change
        // 4. THEN paste into the now-focused text field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSLog("📋 Double-click paste executing after overlay hidden and focus restored")

            // Add haptic feedback
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

            // NOW paste into restored text field
            self.viewModel.pasteItem(self.item)
        }
    }

    private func deleteItem() {
        // Trigger delete animation
        withAnimation(.easeInOut(duration: 0.3)) {
            isDeleting = true
        }

        // Perform actual delete after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            viewModel.deleteItem(item)
        }
    }

    private func pinItem() {
        viewModel.toggleFavorite(for: item)
    }


    // MARK: - Drag and Drop Support

    /// Provides NSItemProvider for drag-and-drop with proper file handling
    private func provideDragData() -> NSItemProvider {
        switch item.content {
        case .image(_):
            // For images, use the pre-cached file path (created async in onAppear)
            // This provides instant drag with zero latency
            if let cachedPath = cachedImagePath {
                let fileURL = URL(fileURLWithPath: cachedPath)
                let provider = NSItemProvider(contentsOf: fileURL)!
                return provider
            } else {
                // Fallback if cache isn't ready yet (shouldn't happen)
                return NSItemProvider(object: "[Image]" as NSString)
            }

        default:
            // For text and other types, provide string data
            return NSItemProvider(object: dragData as NSString)
        }
    }

    private var dragData: String {
        switch item.content {
        case .text(let textContent):
            return textContent.plainText
        case .richText(let richContent):
            return richContent.plainTextFallback
        case .image(_):
            // For images, use cached temporary file path or fallback to description
            return cachedImagePath ?? "[Image: \(item.metadata.preview ?? "Untitled")]"
        case .file(let fileContent):
            // For files, return the file paths as text
            return fileContent.urls.map { $0.path }.joined(separator: "\n")
        case .link(let linkContent):
            return linkContent.url.absoluteString
        case .code(let codeContent):
            return codeContent.code
        case .color(let colorContent):
            return colorContent.hexValue
        case .snippet(let snippetContent):
            return snippetContent.content
        case .multiple(let multiContent):
            // For multiple items, return the first text-like item
            for subItem in multiContent.items {
                switch subItem {
                case .text(let textContent):
                    return textContent.plainText
                case .richText(let richContent):
                    return richContent.plainTextFallback
                case .link(let linkContent):
                    return linkContent.url.absoluteString
                case .code(let codeContent):
                    return codeContent.code
                case .color(let colorContent):
                    return colorContent.hexValue
                default:
                    continue
                }
            }
            return "Multiple items"
        }
    }

    private func createTemporaryImageFile(from imageContent: ImageContent) -> String? {
        do {
            // Create temporary directory
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileName = "\(item.id.uuidString).\(imageContent.format.rawValue)"
            let tempURL = tempDir.appendingPathComponent(tempFileName)

            // Write image data to temporary file
            try imageContent.data.write(to: tempURL)

            return tempURL.path
        } catch {
            print("Failed to create temporary image file: \(error)")
            return nil
        }
    }

    private func createTemporaryImageFileAsync(from imageContent: ImageContent) async -> String? {
        return await Task(priority: .utility) {
            do {
                // Create temporary directory
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileName = "\(item.id.uuidString).\(imageContent.format.rawValue)"
                let tempURL = tempDir.appendingPathComponent(tempFileName)

                // Write image data to temporary file
                try imageContent.data.write(to: tempURL)

                return tempURL.path
            } catch {
                print("Failed to create temporary image file: \(error)")
                return nil
            }
        }.value
    }

    private var dragPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Type badge
            Text(contentTypeInfo.name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(contentTypeInfo.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(contentTypeInfo.color.opacity(0.15))
                )

            // Content preview
            Text(dragPreviewText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Drag indicator
            HStack {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Drag to paste")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var dragPreviewText: String {
        let text = dragData
        let maxLength = 60
        return text.count > maxLength ?
            String(text.prefix(maxLength)) + "..." :
            text
    }

    // MARK: - Source App Icon

    /// Converts stored icon Data (TIFF format) to SwiftUI Image
    private func iconImage(from data: Data) -> Image? {
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
    }

    /// App icon badge view showing the source application
    private var appIconBadge: some View {
        Group {
            if let iconData = item.source.applicationIcon {
                // Debug logging for icon data
                let _ = NSLog("🎯 App icon data - BundleID: \(item.source.applicationBundleID ?? "nil"), Name: \(item.source.applicationName ?? "nil"), Icon size: \(iconData.count) bytes")

                if let iconImage = iconImage(from: iconData) {
                    iconImage
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(colorScheme == .light ?
                                    Color.white.opacity(0.8) :
                                    Color.black.opacity(0.4),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(0.15),
                            radius: 2,
                            x: 0,
                            y: 1
                        )
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showTooltip = hovering
                            }
                        }
                } else {
                    let _ = NSLog("❌ Failed to convert icon data to NSImage for: \(item.source.applicationName ?? "Unknown")")
                    // Fallback when icon data exists but conversion fails
                    Image(systemName: "app.badge")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .light ?
                            Color(.sRGB, red: 0.581, green: 0.639, blue: 0.722, opacity: 1.0) :
                            Color(.sRGB, red: 0.7, green: 0.7, blue: 0.7, opacity: 1.0)
                        )
                        .frame(width: 22, height: 22)
                }
            } else {
                let _ = NSLog("⚠️ No icon data for app: \(item.source.applicationName ?? "Unknown"), BundleID: \(item.source.applicationBundleID ?? "nil")")
                // Fallback to SF Symbol if no app icon available
                Image(systemName: "app.badge")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .light ?
                        Color(.sRGB, red: 0.581, green: 0.639, blue: 0.722, opacity: 1.0) :
                        Color(.sRGB, red: 0.7, green: 0.7, blue: 0.7, opacity: 1.0)
                    )
                    .frame(width: 22, height: 22)
            }
        }
    }

    // MARK: - Color Extraction

    /// Extracts accent color from app icon for card theming
    private func extractAccentColor() async {
        let appName = item.source.applicationName ?? "Unknown"
        NSLog("🎨 Starting color extraction for: \(appName)")

        // Check cache first
        if let bundleID = item.source.applicationBundleID {
            if let cachedColor = await AppIconColorCache.shared.getColor(for: bundleID) {
                NSLog("✅ Using cached color for: \(appName)")
                accentColor = cachedColor
                return
            }
        }

        // Extract color from icon data
        guard let iconData = item.source.applicationIcon else {
            NSLog("⚠️ No icon data to extract color from for: \(appName)")
            return
        }

        guard let nsImage = NSImage(data: iconData) else {
            NSLog("❌ Failed to create NSImage from icon data for: \(appName)")
            return
        }

        guard let extractedColor = nsImage.extractDominantColor() else {
            NSLog("❌ Failed to extract dominant color for: \(appName)")
            return
        }

        NSLog("✅ Successfully extracted color for: \(appName)")

        // Cache the extracted color
        if let bundleID = item.source.applicationBundleID {
            await AppIconColorCache.shared.setColor(extractedColor, for: bundleID)
        }

        accentColor = extractedColor
        NSLog("🎨 Applied accent color to card for: \(appName)")
    }
}

// Custom button style for quick action buttons
struct QuickActionButtonStyle: ButtonStyle {
    let color: Color
    let colorScheme: ColorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(colorScheme == .light ? 
                (configuration.isPressed ? Color.primary.opacity(0.7) : Color.primary.opacity(0.8)) :
                (configuration.isPressed ? Color.primary.opacity(0.6) : Color.primary.opacity(0.7))
            )
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? 
                        (colorScheme == .light ? Color.primary.opacity(0.15) : Color.primary.opacity(0.25)) :
                        (colorScheme == .light ? Color.primary.opacity(0.06) : Color.primary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(configuration.isPressed ? Color.primary.opacity(0.4) : Color.primary.opacity(0.2), lineWidth: configuration.isPressed ? 1 : 0.5)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Content type information for styling
struct ContentTypeInfo {
    let name: String
    let icon: String
    let color: Color

    static func from(_ content: ClipboardContent) -> ContentTypeInfo {
        switch content {
        case .text(let textContent):
            // Check if text is a hex color
            let text = textContent.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if isHexColor(text) {
                return ContentTypeInfo(name: "Color", icon: "paintpalette", color: .pink)
            }
            return ContentTypeInfo(name: "Text", icon: "doc.text", color: .blue)
        case .richText:
            return ContentTypeInfo(name: "Rich Text", icon: "doc.richtext", color: .blue)
        case .image:
            return ContentTypeInfo(name: "Image", icon: "photo", color: .green)
        case .file:
            return ContentTypeInfo(name: "File", icon: "doc", color: .orange)
        case .link:
            return ContentTypeInfo(name: "Link", icon: "link", color: .cyan)
        case .code:
            return ContentTypeInfo(name: "Code", icon: "chevron.left.forwardslash.chevron.right", color: .indigo)
        case .color:
            return ContentTypeInfo(name: "Color", icon: "paintpalette", color: .pink)
        case .snippet:
            return ContentTypeInfo(name: "Snippet", icon: "text.quote", color: .mint)
        case .multiple:
            return ContentTypeInfo(name: "Multiple", icon: "square.stack", color: .gray)
        }
    }

    private static func isHexColor(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), trimmed.count == 7 else { return false }

        let hexValue = String(trimmed.dropFirst())
        return Int(hexValue, radix: 16) != nil
    }
}

