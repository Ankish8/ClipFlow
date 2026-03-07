import Foundation
import ClipFlowCore

// MARK: - Auto-Tag Rule

public struct AutoTagRule: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    /// Match by source app bundle ID (e.g. "com.apple.safari"). Nil = any app.
    public var sourceAppBundleID: String?
    /// Match by content type string (e.g. "link", "image", "text"). Nil = any type.
    public var contentType: String?
    /// Match if item's display text contains this string (case-insensitive). Nil = no text filter.
    public var textPattern: String?
    /// Tag to apply when rule matches.
    public var tagId: UUID

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        sourceAppBundleID: String? = nil,
        contentType: String? = nil,
        textPattern: String? = nil,
        tagId: UUID
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.sourceAppBundleID = sourceAppBundleID
        self.contentType = contentType
        self.textPattern = textPattern
        self.tagId = tagId
    }
}

// MARK: - Auto-Tag Service

@MainActor
public class AutoTagService {
    public static let shared = AutoTagService()

    private static let storageKey = "AutoTagService.rules.v1"
    public private(set) var rules: [AutoTagRule] = []

    private init() {
        loadRules()
    }

    // MARK: - Rule Management

    public func addRule(_ rule: AutoTagRule) {
        rules.append(rule)
        persistRules()
    }

    public func updateRule(_ rule: AutoTagRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            persistRules()
        }
    }

    public func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        persistRules()
    }

    /// Remove rules referencing a deleted tag.
    public func pruneRulesForDeletedTag(tagId: UUID) {
        let before = rules.count
        rules.removeAll { $0.tagId == tagId }
        if rules.count != before { persistRules() }
    }

    // MARK: - Evaluation

    /// Returns tag IDs that should be applied to a new clipboard item.
    public func matchingTagIds(for item: ClipboardItem) -> Set<UUID> {
        var matched = Set<UUID>()
        for rule in rules where rule.isEnabled {
            let appMatch = rule.sourceAppBundleID.map {
                item.source.applicationBundleID?.localizedCaseInsensitiveCompare($0) == .orderedSame
            } ?? true
            let typeMatch = rule.contentType.map {
                item.content.contentType == $0
            } ?? true
            let textMatch = rule.textPattern.map {
                item.content.displayText.localizedCaseInsensitiveContains($0)
            } ?? true

            if appMatch && typeMatch && textMatch {
                matched.insert(rule.tagId)
            }
        }
        return matched
    }

    // MARK: - Persistence

    private func loadRules() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([AutoTagRule].self, from: data)
        else { return }
        rules = decoded
    }

    private func persistRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
