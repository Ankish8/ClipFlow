import Foundation
import CryptoKit

// MARK: - Item Metadata

public struct ItemMetadata: Codable, Hashable, Sendable {
    public let size: Int64
    public let hash: String
    public let preview: String?
    public let mimeType: String?
    public let uti: String?
    public let characterCount: Int?
    public let wordCount: Int?
    public let lineCount: Int?

    public init(
        size: Int64,
        hash: String,
        preview: String? = nil,
        mimeType: String? = nil,
        uti: String? = nil,
        characterCount: Int? = nil,
        wordCount: Int? = nil,
        lineCount: Int? = nil
    ) {
        self.size = size
        self.hash = hash
        self.preview = preview
        self.mimeType = mimeType
        self.uti = uti
        self.characterCount = characterCount
        self.wordCount = wordCount
        self.lineCount = lineCount
    }

    public static func generate(for content: ClipboardContent) -> ItemMetadata {
        let preview = generatePreview(for: content)
        let hash = generateHash(for: content)
        let size = calculateSize(of: content)
        let (charCount, wordCount, lineCount) = calculateTextStats(for: content)

        return ItemMetadata(
            size: size,
            hash: hash,
            preview: preview,
            mimeType: getMimeType(for: content),
            uti: getUTI(for: content),
            characterCount: charCount,
            wordCount: wordCount,
            lineCount: lineCount
        )
    }

    private static func generatePreview(for content: ClipboardContent) -> String? {
        switch content {
        case .text(let textContent):
            return String(textContent.plainText.prefix(200))
        case .richText(let richContent):
            return String(richContent.plainTextFallback.prefix(200))
        case .code(let codeContent):
            return String(codeContent.code.prefix(200))
        case .link(let linkContent):
            return linkContent.title ?? linkContent.url.absoluteString
        case .file(let fileContent):
            return fileContent.fileName
        case .image:
            return "Image"
        case .color(let colorContent):
            return colorContent.hexValue
        case .snippet(let snippetContent):
            return snippetContent.title
        case .multiple(let multiContent):
            return multiContent.description
        }
    }

    private static func generateHash(for content: ClipboardContent) -> String {
        var hasher = SHA256()

        switch content {
        case .text(let textContent):
            hasher.update(data: textContent.plainText.data(using: .utf8) ?? Data())
        case .richText(let richContent):
            hasher.update(data: richContent.rtfData)
        case .image(let imageContent):
            hasher.update(data: imageContent.data)
        case .file(let fileContent):
            let urlString = fileContent.urls.map(\.absoluteString).joined()
            hasher.update(data: urlString.data(using: .utf8) ?? Data())
        case .link(let linkContent):
            hasher.update(data: linkContent.url.absoluteString.data(using: .utf8) ?? Data())
        case .code(let codeContent):
            hasher.update(data: codeContent.code.data(using: .utf8) ?? Data())
        case .color(let colorContent):
            hasher.update(data: colorContent.hexValue.data(using: .utf8) ?? Data())
        case .snippet(let snippetContent):
            hasher.update(data: snippetContent.content.data(using: .utf8) ?? Data())
        case .multiple(let multiContent):
            for item in multiContent.items {
                let itemHash = generateHash(for: item)
                hasher.update(data: itemHash.data(using: .utf8) ?? Data())
            }
        }

        return Data(hasher.finalize()).base64EncodedString()
    }

    private static func calculateSize(of content: ClipboardContent) -> Int64 {
        switch content {
        case .text(let textContent):
            return Int64(textContent.plainText.utf8.count)
        case .richText(let richContent):
            return Int64(richContent.rtfData.count)
        case .image(let imageContent):
            return Int64(imageContent.data.count)
        case .file(let fileContent):
            return fileContent.fileSize
        case .link(let linkContent):
            var size = linkContent.url.absoluteString.utf8.count
            if let title = linkContent.title {
                size += title.utf8.count
            }
            if let description = linkContent.description {
                size += description.utf8.count
            }
            return Int64(size)
        case .code(let codeContent):
            return Int64(codeContent.code.utf8.count)
        case .color:
            return 32 // RGBA values
        case .snippet(let snippetContent):
            return Int64(snippetContent.content.utf8.count)
        case .multiple(let multiContent):
            return multiContent.items.reduce(0) { sum, item in
                sum + calculateSize(of: item)
            }
        }
    }

    private static func calculateTextStats(for content: ClipboardContent) -> (chars: Int?, words: Int?, lines: Int?) {
        let text: String?

        switch content {
        case .text(let textContent):
            text = textContent.plainText
        case .richText(let richContent):
            text = richContent.plainTextFallback
        case .code(let codeContent):
            text = codeContent.code
        case .snippet(let snippetContent):
            text = snippetContent.content
        default:
            return (nil, nil, nil)
        }

        guard let text = text else { return (nil, nil, nil) }

        let chars = text.count
        let words = text.components(separatedBy: .whitespacesAndNewlines)
                       .filter { !$0.isEmpty }.count
        let lines = text.components(separatedBy: .newlines).count

        return (chars, words, lines)
    }

    private static func getMimeType(for content: ClipboardContent) -> String? {
        switch content {
        case .text:
            return "text/plain"
        case .richText:
            return "text/rtf"
        case .image(let imageContent):
            switch imageContent.format {
            case .png: return "image/png"
            case .jpeg: return "image/jpeg"
            case .gif: return "image/gif"
            case .tiff: return "image/tiff"
            case .bmp: return "image/bmp"
            case .heif: return "image/heif"
            case .webp: return "image/webp"
            }
        case .link:
            return "text/uri-list"
        case .code:
            return "text/plain"
        default:
            return nil
        }
    }

    private static func getUTI(for content: ClipboardContent) -> String? {
        switch content {
        case .text:
            return "public.plain-text"
        case .richText:
            return "public.rtf"
        case .image(let imageContent):
            switch imageContent.format {
            case .png: return "public.png"
            case .jpeg: return "public.jpeg"
            case .gif: return "com.compuserve.gif"
            case .tiff: return "public.tiff"
            case .bmp: return "com.microsoft.bmp"
            case .heif: return "public.heif"
            case .webp: return "org.webmproject.webp"
            }
        case .file:
            return "public.file-url"
        case .link:
            return "public.url"
        case .code:
            return "public.source-code"
        default:
            return nil
        }
    }
}

// MARK: - Source Information

public struct ItemSource: Codable, Hashable, Sendable {
    public let applicationBundleID: String?
    public let applicationName: String?
    public let applicationIcon: Data?
    public let deviceID: String
    public let deviceName: String

    public init(
        applicationBundleID: String? = nil,
        applicationName: String? = nil,
        applicationIcon: Data? = nil,
        deviceID: String? = nil,
        deviceName: String? = nil
    ) {
        self.applicationBundleID = applicationBundleID
        self.applicationName = applicationName
        self.applicationIcon = applicationIcon
        self.deviceID = deviceID ?? Self.currentDeviceID()
        self.deviceName = deviceName ?? Self.currentDeviceName()
    }

    internal static func currentDeviceID() -> String {
        if let uuid = IORegistryEntryCreateCFProperty(
            IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/"),
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String {
            return uuid
        }
        return UUID().uuidString
    }

    internal static func currentDeviceName() -> String {
        Host.current().localizedName ?? "Unknown Mac"
    }
}

// MARK: - Timestamps

public struct ItemTimestamps: Codable, Hashable, Sendable {
    public let createdAt: Date
    public var lastAccessedAt: Date?
    public var modifiedAt: Date?
    public var expiresAt: Date?

    public init(
        createdAt: Date = Date(),
        lastAccessedAt: Date? = nil,
        modifiedAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.modifiedAt = modifiedAt
        self.expiresAt = expiresAt
    }

    public mutating func markAccessed() {
        lastAccessedAt = Date()
    }

    public mutating func markModified() {
        modifiedAt = Date()
    }

    public mutating func setExpiration(days: Int) {
        expiresAt = Calendar.current.date(byAdding: .day, value: days, to: Date())
    }
}

// MARK: - Security Metadata

public struct SecurityMetadata: Codable, Hashable, Sendable {
    public let isEncrypted: Bool
    public let isSensitive: Bool
    public let encryptionKeyID: String?
    public let accessControl: AccessControl

    public init(
        isEncrypted: Bool = false,
        isSensitive: Bool = false,
        encryptionKeyID: String? = nil,
        accessControl: AccessControl = .public
    ) {
        self.isEncrypted = isEncrypted
        self.isSensitive = isSensitive
        self.encryptionKeyID = encryptionKeyID
        self.accessControl = accessControl
    }

    public static func detectSensitive(from content: ClipboardContent) -> Bool {
        switch content {
        case .text(let textContent):
            return detectSensitiveText(textContent.plainText)
        case .richText(let richContent):
            return detectSensitiveText(richContent.plainTextFallback)
        case .code(let codeContent):
            return detectSensitiveCode(codeContent.code)
        default:
            return false
        }
    }

    private static func detectSensitiveText(_ text: String) -> Bool {
        let sensitivePatterns = [
            #"(?i)(password|pwd|pass)\s*[:=]\s*\S+"#,
            #"(?i)(api[_-]?key|token)\s*[:=]\s*\S+"#,
            #"\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b"#, // Credit card
            #"\b\d{3}-\d{2}-\d{4}\b"#, // SSN
        ]

        return sensitivePatterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func detectSensitiveCode(_ code: String) -> Bool {
        let codePatterns = [
            #"(?i)(private[_-]?key|secret[_-]?key)\s*[:=]"#,
            #"(?i)(client[_-]?secret|app[_-]?secret)\s*[:=]"#,
            #"-----BEGIN (RSA )?PRIVATE KEY-----"#,
        ]

        return codePatterns.contains { pattern in
            code.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

public enum AccessControl: String, Codable, CaseIterable, Sendable {
    case `public`, `private`, shared, restricted
}