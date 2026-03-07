import SwiftUI
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
                VStack(spacing: 8) {
                    Image(systemName: "tag.square")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No auto-tag rules yet")
                        .font(.headline)
                    Text("Rules automatically tag new clipboard items\nbased on source app or content type.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                List {
                    ForEach(rules) { rule in
                        AutoTagRuleRow(
                            rule: rule,
                            tagName: availableTags.first(where: { $0.id == rule.tagId })?.name ?? "Unknown",
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
            availableTags = TagService.shared.getAllTags()
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
        if let app = rule.sourceAppBundleID {
            // Show just the app name part of bundle ID for readability
            let name = app.components(separatedBy: ".").last ?? app
            parts.append("App: \(name)")
        }
        if let type = rule.contentType {
            parts.append("Type: \(type)")
        }
        return parts.isEmpty ? "Matches all items" : parts.joined(separator: " · ")
    }
}

// MARK: - Add Rule Sheet

private struct AddAutoTagRuleSheet: View {
    let availableTags: [Tag]
    let onSave: (AutoTagRule) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedTagId: UUID?
    @State private var appBundleID = ""
    @State private var selectedContentType = ""

    private let contentTypes = ["", "text", "richText", "image", "file", "link", "code", "color"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Rule Name") {
                    TextField("e.g. Tag Safari links", text: $name)
                }

                Section("Match Conditions") {
                    TextField("Source App Bundle ID (optional)", text: $appBundleID)
                        .font(.system(.body, design: .monospaced))
                    Text("e.g. com.apple.Safari, com.microsoft.VSCode")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Picker("Content Type", selection: $selectedContentType) {
                        Text("Any").tag("")
                        ForEach(contentTypes.dropFirst(), id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                }

                Section("Apply Tag") {
                    Picker("Tag", selection: $selectedTagId) {
                        Text("Select a tag...").tag(nil as UUID?)
                        ForEach(availableTags) { tag in
                            Text(tag.name).tag(tag.id as UUID?)
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
                        sourceAppBundleID: appBundleID.isEmpty ? nil : appBundleID,
                        contentType: selectedContentType.isEmpty ? nil : selectedContentType,
                        tagId: tagId
                    )
                    onSave(rule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTagId == nil || name.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 380)
    }
}
