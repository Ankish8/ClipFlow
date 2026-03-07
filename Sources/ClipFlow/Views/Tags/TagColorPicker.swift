import SwiftUI
import ClipFlowCore

/// Color picker for selecting tag colors
struct TagColorPicker: View {
    @Binding var selectedColor: TagColor
    let onColorSelected: ((TagColor) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    init(selectedColor: Binding<TagColor>, onColorSelected: ((TagColor) -> Void)? = nil) {
        self._selectedColor = selectedColor
        self.onColorSelected = onColorSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tag Color")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 32), spacing: 8)
            ], spacing: 8) {
                ForEach(TagColor.allCases, id: \.self) { color in
                    colorButton(for: color)
                }
            }
        }
        .padding(12)
    }

    private func colorButton(for color: TagColor) -> some View {
        let isSelected = selectedColor == color
        let swiftUIColor = color.adaptiveSwiftUIColor(for: colorScheme)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedColor = color
                onColorSelected?(color)
            }
        }) {
            ZStack {
                Circle()
                    .fill(swiftUIColor)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Circle()
                            .stroke(color.indicatorBorderColor(for: colorScheme), lineWidth: 0.9)
                    }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.glass(.regular.tint(swiftUIColor)))
        .help(color.displayName)
    }
}

// MARK: - Standalone Color Picker Menu

/// A compact color picker that can be used in context menus
struct TagColorPickerMenu: View {
    @Binding var selectedColor: TagColor
    let onColorSelected: ((TagColor) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    init(selectedColor: Binding<TagColor>, onColorSelected: ((TagColor) -> Void)? = nil) {
        self._selectedColor = selectedColor
        self.onColorSelected = onColorSelected
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TagColor.allCases, id: \.self) { color in
                let swiftUIColor = color.adaptiveSwiftUIColor(for: colorScheme)

                Button(action: {
                    selectedColor = color
                    onColorSelected?(color)
                }) {
                    Circle()
                        .fill(swiftUIColor)
                        .frame(width: 20, height: 20)
                        .overlay {
                            Circle()
                                .stroke(color.indicatorBorderColor(for: colorScheme), lineWidth: 0.8)
                        }
                }
                .buttonStyle(.glass(.regular.tint(swiftUIColor)))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Color Picker") {
    VStack(spacing: 20) {
        TagColorPicker(selectedColor: .constant(.blue))

        TagColorPicker(selectedColor: .constant(.red))
    }
    .padding()
    .frame(width: 250)
}

#Preview("Color Picker Menu") {
    TagColorPickerMenu(selectedColor: .constant(.purple))
        .padding()
}
