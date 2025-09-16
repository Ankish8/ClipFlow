import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    @State private var isSearching = false

    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search clipboard history...", text: $text)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        // Trigger full-text search on enter
                        isSearching = true
                    }

                if !text.isEmpty {
                    Button {
                        text = ""
                        isSearching = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            if isSearching {
                Button("Search") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSearching)
    }

    private func performSearch() {
        // This would trigger a more comprehensive search
        isSearching = false
    }
}