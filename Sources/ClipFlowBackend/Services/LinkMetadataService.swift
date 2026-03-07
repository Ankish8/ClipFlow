import Foundation

// MARK: - Link Metadata Service

@MainActor
public class LinkMetadataService {
    public static let shared = LinkMetadataService()

    /// In-memory cache keyed by URL string.
    private var cache: [String: LinkMeta] = [:]

    private init() {}

    public struct LinkMeta: Sendable {
        public let title: String?
        public let description: String?
        public let faviconData: Data?
        public let previewImageData: Data?
    }

    /// Fetch Open Graph / meta-tag metadata for a URL. Results are cached in memory.
    public func fetchMetadata(for url: URL) async -> LinkMeta {
        let key = url.absoluteString
        if let cached = cache[key] { return cached }

        let meta = await Task.detached(priority: .utility) {
            await Self.performFetch(url: url)
        }.value

        cache[key] = meta
        return meta
    }

    // MARK: - Private (nonisolated — runs on background thread inside Task.detached)

    /// Must be nonisolated so Task.detached actually runs this off MainActor.
    /// Without nonisolated, static methods inherit @MainActor from the class,
    /// causing the detached task to hop right back to MainActor for networking.
    nonisolated private static func performFetch(url: URL) async -> LinkMeta {
        var request = URLRequest(url: url, timeoutInterval: 8)
        // Use a real browser User-Agent — many sites serve minimal HTML or block non-browser requests
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else {
            return LinkMeta(title: nil, description: nil, faviconData: nil, previewImageData: nil)
        }

        let title = extractMeta(from: html, patterns: [
            #"<meta[^>]+property="og:title"[^>]+content="([^"]*?)""#,
            #"<meta[^>]+content="([^"]*?)"[^>]+property="og:title""#,
            #"<meta[^>]+name="twitter:title"[^>]+content="([^"]*?)""#,
            #"<title[^>]*>([^<]+)</title>"#
        ])

        let description = extractMeta(from: html, patterns: [
            #"<meta[^>]+property="og:description"[^>]+content="([^"]*?)""#,
            #"<meta[^>]+content="([^"]*?)"[^>]+property="og:description""#,
            #"<meta[^>]+name="description"[^>]+content="([^"]*?)""#
        ])

        // Fetch OG image URL from meta tags
        let ogImageURL = extractMeta(from: html, patterns: [
            #"<meta[^>]+property="og:image"[^>]+content="([^"]*?)""#,
            #"<meta[^>]+content="([^"]*?)"[^>]+property="og:image""#,
            #"<meta[^>]+name="twitter:image"[^>]+content="([^"]*?)""#
        ])

        // Fetch OG image and favicon in parallel
        async let faviconResult = fetchFavicon(for: url)
        async let ogImageResult = fetchOGImage(urlString: ogImageURL, baseURL: url)

        let favicon = await faviconResult
        let ogImage = await ogImageResult

        return LinkMeta(title: title, description: description, faviconData: favicon, previewImageData: ogImage)
    }

    nonisolated private static func extractMeta(from html: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html)
            else { continue }

            let value = String(html[range])
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    nonisolated private static func fetchFavicon(for url: URL) async -> Data? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        guard let faviconURL = components.url else { return nil }

        var request = URLRequest(url: faviconURL, timeoutInterval: 4)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              !data.isEmpty
        else { return nil }

        return data
    }

    nonisolated private static func fetchOGImage(urlString: String?, baseURL: URL) async -> Data? {
        guard let urlString = urlString, !urlString.isEmpty else { return nil }

        // Resolve relative URLs against the base
        let imageURL: URL?
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            imageURL = URL(string: urlString)
        } else if urlString.hasPrefix("//") {
            imageURL = URL(string: "https:" + urlString)
        } else {
            imageURL = URL(string: urlString, relativeTo: baseURL)
        }

        guard let url = imageURL else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              data.count > 100  // Skip tiny placeholder images
        else { return nil }

        // Cap at 2MB to avoid storing huge images
        guard data.count <= 2_000_000 else { return nil }

        return data
    }
}
