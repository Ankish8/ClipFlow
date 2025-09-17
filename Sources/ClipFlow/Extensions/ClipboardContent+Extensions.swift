import Foundation
import ClipFlowCore

extension ClipboardContent {
    var displayText: String {
        switch self {
        case .text(let content):
            return content.plainText
        case .richText(let content):
            return content.plainTextFallback
        case .image(let content):
            return "Image (\(content.format))"
        case .file(let content):
            let names = content.urls.map { $0.lastPathComponent }
            return names.joined(separator: ", ")
        case .link(let content):
            return content.url.absoluteString
        case .code(let content):
            return content.code
        case .color(let content):
            return content.hexString
        case .snippet(let content):
            return content.content
        case .multiple(let content):
            return "Multiple items (\(content.items.count))"
        }
    }

    var typeDisplayName: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .file: return "File"
        case .link: return "Link"
        case .code: return "Code"
        case .color: return "Color"
        case .snippet: return "Snippet"
        case .multiple: return "Multiple Items"
        }
    }
}

extension ColorContent {
    var hexString: String {
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

