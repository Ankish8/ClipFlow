import SwiftUI
import ClipFlowCore

/// Color picker for selecting tag colors
struct TagColorPicker: View {
    @Binding var selectedColor: TagColor
    let onColorSelected: ((TagColor) -> Void)?

    @Environment(\.colorScheme) var colorScheme

    init(selectedColor: Binding<TagColor>, onColorSelected: ((TagColor) -> Void)? = nil) {
        self._selectedColor = selectedColor
        self.onColorSelected = onColorSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tag Color")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 32), spacing: 8)
            ], spacing: 8) {
                ForEach(TagColor.allCases, id: \.self) { color in
                    colorButton(for: color)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(colorScheme == .light ? 0.04 : 0.08))
        )
    }

    private func colorButton(for color: TagColor) -> some View {
        let isSelected = selectedColor == color
        let (r, g, b) = color.rgbComponents
        let swiftUIColor = Color(red: r, green: g, blue: b)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedColor = color
                onColorSelected?(color)
            }
        }) {
            ZStack {
                // Color circle
                Circle()
                    .fill(swiftUIColor)
                    .frame(width: 28, height: 28)

                // Checkmark if selected
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }

                // Border
                Circle()
                    .stroke(
                        isSelected ?
                            Color.primary.opacity(0.3) :
                            Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .focusEffectDisabled()
        .help(color.displayName)
    }
}

// MARK: - Standalone Color Picker Menu

/// A compact color picker that can be used in context menus
struct TagColorPickerMenu: View {
    @Binding var selectedColor: TagColor
    let onColorSelected: ((TagColor) -> Void)?

    init(selectedColor: Binding<TagColor>, onColorSelected: ((TagColor) -> Void)? = nil) {
        self._selectedColor = selectedColor
        self.onColorSelected = onColorSelected
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TagColor.allCases, id: \.self) { color in
                let isSelected = selectedColor == color
                let (r, g, b) = color.rgbComponents
                let swiftUIColor = Color(red: r, green: g, blue: b)

                Button(action: {
                    selectedColor = color
                    onColorSelected?(color)
                }) {
                    ZStack {
                        Circle()
                            .fill(swiftUIColor)
                            .frame(width: 20, height: 20)

                        if isSelected {
                            Circle()
                                .stroke(Color.primary, lineWidth: 2)
                                .frame(width: 22, height: 22)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
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
