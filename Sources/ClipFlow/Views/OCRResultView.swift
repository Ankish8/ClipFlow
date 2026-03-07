import SwiftUI

/// Displays OCR-extracted text with copy and close actions.
struct OCRResultView: View {
    let text: String
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extracted Text")
                .font(.headline)
                .padding([.top, .horizontal])

            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            HStack {
                Button("Copy to Clipboard", action: onCopy)
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Close", action: onClose)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 360, minHeight: 240)
    }
}
