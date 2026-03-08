import SwiftUI
import AppKit
import ClipFlowCore
import ClipFlowBackend

// MARK: - Auto-Tag Rules Settings View

struct AutoTagRulesView: View {
    @State private var rules: [AutoTagRule] = []
    @State private var availableTags: [Tag] = []
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if rules.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "tag.square")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No auto-tag rules yet")
                        .font(.title3.weight(.semibold))
                    Text("Rules automatically tag new clipboard items\nbased on keywords, source app, or content type.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Examples")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        RuleSuggestionRow(icon: "link", text: "Tag links — text contains \"https://\"")
                        RuleSuggestionRow(icon: "key.fill", text: "Flag API keys — text contains \"sk-\"")
                        RuleSuggestionRow(icon: "photo", text: "Tag all images — content type is Image")
                        RuleSuggestionRow(icon: "at", text: "Catch emails — text contains \"@\"")
                        RuleSuggestionRow(icon: "app.dashed", text: "Tag by app — source app is Safari")
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer()
            } else {
                let tagNameMap = Dictionary(uniqueKeysWithValues: availableTags.map { ($0.id, $0.name) })
                List {
                    ForEach(rules) { rule in
                        AutoTagRuleRow(
                            rule: rule,
                            tagName: tagNameMap[rule.tagId] ?? "Unknown",
                            onToggle: { updated in
                                AutoTagService.shared.updateRule(updated)
                                rules = AutoTagService.shared.rules
                            },
                            onDelete: { id in
                                AutoTagService.shared.deleteRule(id: id)
                                rules = AutoTagService.shared.rules
                            }
                        )
                    }
                }
            }

            HStack {
                Spacer()
                Button("Add Rule") { showAddSheet = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .sheet(isPresented: $showAddSheet) {
            AddAutoTagRuleSheet(availableTags: availableTags) { newRule in
                AutoTagService.shared.addRule(newRule)
                rules = AutoTagService.shared.rules
            }
        }
        .onAppear {
            rules = AutoTagService.shared.rules
            Task {
                await TagService.shared.loadAllTags()
                availableTags = TagService.shared.getAllTags()
            }
        }
    }
}

// MARK: - Rule Suggestion Row

private struct RuleSuggestionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(width: 18)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Rule Row

private struct AutoTagRuleRow: View {
    let rule: AutoTagRule
    let tagName: String
    let onToggle: (AutoTagRule) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("→ \(tagName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { var r = rule; r.isEnabled = $0; onToggle(r) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button(role: .destructive) { onDelete(rule.id) } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let pattern = rule.textPattern, !pattern.isEmpty {
            parts.append("Contains: \(pattern)")
        }
        if let app = rule.sourceAppBundleID {
            let name = app.components(separatedBy: ".").last ?? app
            parts.append("App: \(name)")
        }
        if let type = rule.contentType {
            parts.append("Type: \(type)")
        }
        return parts.isEmpty ? "Matches all items" : parts.joined(separator: " · ")
    }
}

// MARK: - Known App (for picker)

private struct KnownApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

// MARK: - Add Rule Sheet

private struct AddAutoTagRuleSheet: View {
    let availableTags: [Tag]
    let onSave: (AutoTagRule) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var textPattern = ""
    @State private var selectedTagId: UUID?
    @State private var selectedAppBundleID = ""
    @State private var selectedContentType = ""
    @State private var knownApps: [KnownApp] = []
    @State private var loadedTags: [Tag] = []

    private static let contentTypeLabels: [(value: String, label: String)] = [
        ("", "Any"),
        ("text", "Text"),
        ("richText", "Rich Text"),
        ("image", "Image"),
        ("file", "File"),
        ("link", "Link"),
        ("code", "Code"),
        ("color", "Color"),
    ]

    private var tags: [Tag] { loadedTags.isEmpty ? availableTags : loadedTags }
    private var canSave: Bool { selectedTagId != nil && !name.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Rule") {
                    TextField("Name", text: $name, prompt: Text("e.g. Tag API Keys"))

                    if tags.isEmpty {
                        Text("No tags yet — create one in the overlay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Tag", selection: $selectedTagId) {
                            Text("Select a tag…").tag(nil as UUID?)
                            ForEach(tags) { tag in
                                Text(tag.name).tag(tag.id as UUID?)
                            }
                        }
                    }
                }

                Section("Conditions") {
                    TextField("Text contains", text: $textPattern, prompt: Text("keyword or phrase"))

                    Picker("Source App", selection: $selectedAppBundleID) {
                        Text("Any").tag("")
                        ForEach(knownApps) { app in
                            Text(app.name).tag(app.bundleID)
                        }
                    }

                    Picker("Content Type", selection: $selectedContentType) {
                        ForEach(Self.contentTypeLabels, id: \.value) { item in
                            Text(item.label).tag(item.value)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    guard let tagId = selectedTagId, !name.isEmpty else { return }
                    let rule = AutoTagRule(
                        name: name,
                        sourceAppBundleID: selectedAppBundleID.isEmpty ? nil : selectedAppBundleID,
                        contentType: selectedContentType.isEmpty ? nil : selectedContentType,
                        textPattern: textPattern.isEmpty ? nil : textPattern,
                        tagId: tagId
                    )
                    onSave(rule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 440, height: 380)
        .onAppear {
            loadKnownApps()
            Task {
                await TagService.shared.loadAllTags()
                loadedTags = TagService.shared.getAllTags()
            }
        }
    }

    private func loadKnownApps() {
        var seen = Set<String>()
        var apps: [KnownApp] = []
        for runningApp in NSWorkspace.shared.runningApplications {
            guard let bundleID = runningApp.bundleIdentifier,
                  let name = runningApp.localizedName,
                  !seen.contains(bundleID),
                  runningApp.activationPolicy == .regular
            else { continue }
            seen.insert(bundleID)
            apps.append(KnownApp(bundleID: bundleID, name: name))
        }
        knownApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
