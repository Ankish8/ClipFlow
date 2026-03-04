import SwiftUI

/// Always-visible inline search field for the tag bar.
/// Auto-focuses when it appears so users can start typing immediately.
struct ExpandableSearchBar: View {
    @Binding var searchText: String

    let placeholder: String
    let onSearch: ((String) -> Void)?

    @FocusState private var isTextFieldFocused: Bool

    init(
        searchText: Binding<String>,
        placeholder: String = "Search...",
        onSearch: ((String) -> Void)? = nil
    ) {
        self._searchText = searchText
        self.placeholder = placeholder
        self.onSearch = onSearch
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isTextFieldFocused)
                .focusEffectDisabled()
                .onSubmit { onSearch?(searchText) }
                .frame(minWidth: 120, maxWidth: 200)

            if !searchText.isEmpty {
                Button(action: clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(Color.accentColor.opacity(0.15)).interactive(), in: .capsule)
        .animation(.easeInOut(duration: 0.1), value: searchText.isEmpty)
        .onAppear {
            // Small delay lets the view settle into the hierarchy before claiming focus
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                isTextFieldFocused = true
            }
        }
    }

    private func clearSearch() {
        searchText = ""
        onSearch?("")
        isTextFieldFocused = true
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ExpandableSearchBar(
            searchText: .constant(""),
            placeholder: "Search clipboard..."
        )

        ExpandableSearchBar(
            searchText: .constant("swift"),
            placeholder: "Search clipboard..."
        )
    }
    .padding()
    .frame(width: 400)
}
