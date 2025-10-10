import SwiftUI

/// Expandable search bar that collapses to an icon and expands inline
struct ExpandableSearchBar: View {
    @Binding var searchText: String
    @Binding var isExpanded: Bool

    let placeholder: String
    let onSearch: ((String) -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isTextFieldFocused: Bool
    @State private var searchTask: Task<Void, Never>?

    init(
        searchText: Binding<String>,
        isExpanded: Binding<Bool> = .constant(false),
        placeholder: String = "Search...",
        onSearch: ((String) -> Void)? = nil
    ) {
        self._searchText = searchText
        self._isExpanded = isExpanded
        self.placeholder = placeholder
        self.onSearch = onSearch
    }

    var body: some View {
        HStack(spacing: 0) {
            if isExpanded {
                expandedView
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity),
                        removal: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity)
                    ))
            } else {
                collapsedView
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
    }

    // MARK: - Collapsed View (Icon Only)

    private var collapsedView: some View {
        Button(action: expandSearch) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))

                Text("Search")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .light ? 0.04 : 0.08))
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .focusEffectDisabled()
    }

    // MARK: - Expanded View (Search Field)

    private var expandedView: some View {
        HStack(spacing: 8) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            // Text field
            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isTextFieldFocused)
                .onSubmit {
                    // Cancel any pending debounced search
                    searchTask?.cancel()
                    // Perform immediate search on Enter
                    performSearch()
                }
                .onChange(of: searchText) { newValue in
                    // Cancel previous search task
                    searchTask?.cancel()

                    // Debounce search by 300ms
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)

                        // Check if task wasn't cancelled and value didn't change
                        if !Task.isCancelled && searchText == newValue {
                            await MainActor.run {
                                performSearch()
                            }
                        }
                    }
                }
                .frame(minWidth: 120, maxWidth: 200)

            // Clear button (if text exists)
            if !searchText.isEmpty {
                Button(action: clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }

            // Close button
            Button(action: collapseSearch) {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.primary.opacity(colorScheme == .light ? 0.06 : 0.12))
                .overlay(
                    Capsule()
                        .stroke(Color.customAccent.opacity(0.3), lineWidth: 1.5)
                )
        )
        .onAppear {
            isTextFieldFocused = true
        }
    }

    // MARK: - Actions

    private func expandSearch() {
        withAnimation {
            isExpanded = true
        }
    }

    private func collapseSearch() {
        withAnimation {
            isExpanded = false
            isTextFieldFocused = false
        }
    }

    private func clearSearch() {
        searchText = ""
        onSearch?("")
    }

    private func performSearch() {
        onSearch?(searchText)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        // Collapsed state
        ExpandableSearchBar(
            searchText: .constant(""),
            isExpanded: .constant(false)
        )

        // Expanded state
        ExpandableSearchBar(
            searchText: .constant(""),
            isExpanded: .constant(true)
        )

        // Expanded with text
        ExpandableSearchBar(
            searchText: .constant("clipboard"),
            isExpanded: .constant(true)
        )

        // Interactive demo
        StatefulPreviewWrapper()
    }
    .padding()
    .frame(width: 400)
}

// Helper for interactive preview
private struct StatefulPreviewWrapper: View {
    @State private var searchText = ""
    @State private var isExpanded = false

    var body: some View {
        ExpandableSearchBar(
            searchText: $searchText,
            isExpanded: $isExpanded,
            placeholder: "Search clipboard...",
            onSearch: { query in
                print("Searching for: \(query)")
            }
        )
    }
}
