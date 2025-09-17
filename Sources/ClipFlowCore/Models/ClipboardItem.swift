import Foundation
import AppKit

// MARK: - Core ClipboardItem Model

public struct ClipboardItem: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let content: ClipboardContent
    public let metadata: ItemMetadata
    public let source: ItemSource
    public var timestamps: ItemTimestamps
    public var security: SecurityMetadata
    public var tags: Set<String>
    public var collectionIds: Set<UUID>
    public var isFavorite: Bool
    public var isPinned: Bool
    public var isDeleted: Bool

    public init(
        id: UUID = UUID(),
        content: ClipboardContent,
        metadata: ItemMetadata,
        source: ItemSource,
        timestamps: ItemTimestamps = ItemTimestamps(),
        security: SecurityMetadata = SecurityMetadata(),
        tags: Set<String> = [],
        collectionIds: Set<UUID> = [],
        isFavorite: Bool = false,
        isPinned: Bool = false,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.content = content
        self.metadata = metadata
        self.source = source
        self.timestamps = timestamps
        self.security = security
        self.tags = tags
        self.collectionIds = collectionIds
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.isDeleted = isDeleted
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Tag Management
    
    public mutating func addTag(_ tag: String) {
        tags.insert(tag)
        timestamps.markModified()
    }
    
    public mutating func addTags(_ newTags: Set<String>) {
        tags.formUnion(newTags)
        timestamps.markModified()
    }
    
    public mutating func removeTag(_ tag: String) {
        tags.remove(tag)
        timestamps.markModified()
    }
    
    public mutating func removeTags(_ tagsToRemove: Set<String>) {
        tags.subtract(tagsToRemove)
        timestamps.markModified()
    }
    
    public mutating func setTags(_ newTags: Set<String>) {
        tags = newTags
        timestamps.markModified()
    }
    
    public func hasTag(_ tag: String) -> Bool {
        tags.contains(tag)
    }
    
    public func hasAnyTag(_ tagsToCheck: Set<String>) -> Bool {
        !tags.isDisjoint(with: tagsToCheck)
    }
    
    public func hasAllTags(_ tagsToCheck: Set<String>) -> Bool {
        tagsToCheck.isSubset(of: tags)
    }
}

// MARK: - ClipboardContent Types

public enum ClipboardContent: Codable, Hashable, Sendable {
    case text(TextContent)
    case richText(RichTextContent)
    case image(ImageContent)
    case file(FileContent)
    case link(LinkContent)
    case code(CodeContent)
    case color(ColorContent)
    case snippet(SnippetContent)
    case multiple(MultiContent)

    public var contentType: String {
        switch self {
        case .text: return "text"
        case .richText: return "richText"
        case .image: return "image"
        case .file: return "file"
        case .link: return "link"
        case .code: return "code"
        case .color: return "color"
        case .snippet: return "snippet"
        case .multiple: return "multiple"
        }
    }

    public var displayText: String {
        switch self {
        case .text(let content):
            return content.plainText
        case .richText(let content):
            return content.plainTextFallback
        case .image(let content):
            return "Image (\(Int(content.dimensions.width))x\(Int(content.dimensions.height)))"
        case .file(let content):
            return content.fileName
        case .link(let content):
            return content.url.absoluteString
        case .code(let content):
            return content.code
        case .color(let content):
            return content.hexValue
        case .snippet(let content):
            return content.title
        case .multiple(let content):
            return "\(content.items.count) items"
        }
    }
}

public struct TextContent: Codable, Hashable, Sendable {
    public let plainText: String
    public let encoding: String
    public let language: String?
    public let isEmail: Bool
    public let isPhoneNumber: Bool
    public let isURL: Bool

    public init(
        plainText: String,
        encoding: String = "utf-8",
        language: String? = nil,
        isEmail: Bool = false,
        isPhoneNumber: Bool = false,
        isURL: Bool = false
    ) {
        self.plainText = plainText
        self.encoding = encoding
        self.language = language
        self.isEmail = isEmail
        self.isPhoneNumber = isPhoneNumber
        self.isURL = isURL
    }
}

public struct RichTextContent: Codable, Hashable, Sendable {
    public let rtfData: Data
    public let htmlString: String?
    public let attributedStringData: Data
    public let plainTextFallback: String

    public init(
        rtfData: Data,
        htmlString: String? = nil,
        attributedStringData: Data,
        plainTextFallback: String
    ) {
        self.rtfData = rtfData
        self.htmlString = htmlString
        self.attributedStringData = attributedStringData
        self.plainTextFallback = plainTextFallback
    }
}

public struct ImageContent: Codable, Hashable, Sendable {
    public let data: Data
    public let format: ImageFormat
    public let dimensions: CGSize
    public let thumbnailPath: String
    public let colorPalette: [String]
    public let hasTransparency: Bool

    public init(
        data: Data,
        format: ImageFormat,
        dimensions: CGSize,
        thumbnailPath: String,
        colorPalette: [String] = [],
        hasTransparency: Bool = false
    ) {
        self.data = data
        self.format = format
        self.dimensions = dimensions
        self.thumbnailPath = thumbnailPath
        self.colorPalette = colorPalette
        self.hasTransparency = hasTransparency
    }
}

public enum ImageFormat: String, Codable, CaseIterable, Sendable {
    case png, jpeg, gif, tiff, bmp, heif, webp
}

public struct FileContent: Codable, Hashable, Sendable {
    public let urls: [URL]
    public let fileName: String
    public let fileSize: Int64
    public let fileType: String
    public let isDirectory: Bool

    public init(
        urls: [URL],
        fileName: String,
        fileSize: Int64,
        fileType: String,
        isDirectory: Bool
    ) {
        self.urls = urls
        self.fileName = fileName
        self.fileSize = fileSize
        self.fileType = fileType
        self.isDirectory = isDirectory
    }
}

public struct LinkContent: Codable, Hashable, Sendable {
    public let url: URL
    public let title: String?
    public let description: String?
    public let faviconData: Data?
    public let previewImageData: Data?

    public init(
        url: URL,
        title: String? = nil,
        description: String? = nil,
        faviconData: Data? = nil,
        previewImageData: Data? = nil
    ) {
        self.url = url
        self.title = title
        self.description = description
        self.faviconData = faviconData
        self.previewImageData = previewImageData
    }
}

public struct CodeContent: Codable, Hashable, Sendable {
    public let code: String
    public let language: String
    public let syntaxHighlightedData: Data?
    public let repository: String?

    public init(
        code: String,
        language: String,
        syntaxHighlightedData: Data? = nil,
        repository: String? = nil
    ) {
        self.code = code
        self.language = language
        self.syntaxHighlightedData = syntaxHighlightedData
        self.repository = repository
    }
}

public struct ColorContent: Codable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    public let hexValue: String

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.hexValue = String(format: "#%02X%02X%02X",
                              Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    public init(nsColor: NSColor) {
        let rgba = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        self.red = Double(rgba.redComponent)
        self.green = Double(rgba.greenComponent)
        self.blue = Double(rgba.blueComponent)
        self.alpha = Double(rgba.alphaComponent)
        self.hexValue = String(format: "#%02X%02X%02X",
                              Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

public struct SnippetContent: Codable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let content: String
    public let placeholders: [Placeholder]
    public let keyword: String?
    public let category: String
    public let usageCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        placeholders: [Placeholder] = [],
        keyword: String? = nil,
        category: String = "General",
        usageCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.placeholders = placeholders
        self.keyword = keyword
        self.category = category
        self.usageCount = usageCount
    }
}

public struct MultiContent: Codable, Hashable, Sendable {
    public let items: [ClipboardContent]
    public let description: String

    public init(items: [ClipboardContent], description: String) {
        self.items = items
        self.description = description
    }
}

public struct Placeholder: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let defaultValue: String?
    public let type: PlaceholderType
    public let validation: String?

    public init(
        id: String,
        name: String,
        defaultValue: String? = nil,
        type: PlaceholderType = .text,
        validation: String? = nil
    ) {
        self.id = id
        self.name = name
        self.defaultValue = defaultValue
        self.type = type
        self.validation = validation
    }
}

public enum PlaceholderType: String, Codable, CaseIterable, Sendable {
    case text, date, time, number, email, url, selection
}