import SwiftUI
import ClipFlowCore

/// A colored chip button representing a tag
struct TagChipView: View {
    let tag: Tag
    let itemCount: Int
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: (() -> Void)?
    let onDrop: ((UUID) -> Void)?  // Called when an item is dropped on this tag
    let onRename: ((String, @escaping (Bool) -> Void) -> Void)?  // Called when tag is renamed, with completion handler
    let onColorChange: ((TagColor) -> Void)?  // Called when color is changed
    @Binding var showColorPicker: Bool  // External control for showing color picker

    @State private var isHovering = false
    @State private var isDropTarget = false
    @State private var isRenaming = false
    @State private var editingName = ""
    @State private var displayName = ""  // Optimistic UI update
    @State private var selectedColorForEdit: TagColor  // Current color being edited
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    init(
        tag: Tag,
        itemCount: Int = 0,
        isSelected: Bool = false,
        showColorPicker: Binding<Bool> = .constant(false),
        onTap: @escaping () -> Void,
        onLongPress: (() -> Void)? = nil,
        onDrop: ((UUID) -> Void)? = nil,
        onRename: ((String, @escaping (Bool) -> Void) -> Void)? = nil,
        onColorChange: ((TagColor) -> Void)? = nil
    ) {
        self.tag = tag
        self.itemCount = itemCount
        self.isSelected = isSelected
        self._showColorPicker = showColorPicker
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.onDrop = onDrop
        self.onRename = onRename
        self.onColorChange = onColorChange
        self._displayName = State(initialValue: tag.name)
        self._selectedColorForEdit = State(initialValue: tag.color)
    }

    var body: some View {
        HStack(spacing: 6) {
            // Tag color indicator - clickable to open color picker
            Circle()
                .fill(tagColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                )
                .onTapGesture {
                    openColorPicker()
                }
                .popover(isPresented: $showColorPicker) {
                    VStack(spacing: 0) {
                        TagColorPicker(selectedColor: $selectedColorForEdit) { newColor in
                            handleColorChange(newColor)
                        }
                    }
                    .frame(width: 220)
                }
                .help("Click to change color")

            // Tag name or inline editor
            if isRenaming {
                TextField("", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        saveRename()
                    }
                    .onKeyPress(.escape) {
                        cancelRename()
                        return .handled
                    }
                    .frame(minWidth: 40, maxWidth: 120)
            } else {
                Text(displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundColor(textColor)
                    .onTapGesture(count: 2) {
                        startRename()
                    }
                    .onTapGesture {
                        if !isRenaming {
                            onTap()
                        }
                    }
            }

            // Item count badge (if > 0)
            if itemCount > 0 && !isRenaming {
                Text("\(itemCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(badgeTextColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(badgeBackgroundColor)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(chipBackground)
        .overlay(chipBorder)
        .onHover { hovering in
            isHovering = hovering
        }
        .dropDestination(for: String.self) { items, location in
            NSLog("🎯 DROP: TagChipView '\(tag.name)' received \(items.count) items")
            guard let itemIdString = items.first else {
                NSLog("❌ DROP: No items")
                return false
            }
            NSLog("🎯 DROP: Item string: \(itemIdString)")
            guard let itemId = UUID(uuidString: itemIdString) else {
                NSLog("❌ DROP: Invalid UUID: \(itemIdString)")
                return false
            }
            NSLog("✅ DROP: Calling onDrop for '\(tag.name)'")
            onDrop?(itemId)
            return true
        } isTargeted: { isTargeted in
            NSLog("🎯 DROP TARGET: '\(tag.name)' isTargeted = \(isTargeted)")
            isDropTarget = isTargeted
        }
        .help(tag.name)
        .onChange(of: tag.name) { newName in
            // Sync displayName when tag is updated from parent
            if !isRenaming {
                displayName = newName
            }
        }
    }

    // MARK: - Color Computations

    private var tagColor: Color {
        let (r, g, b) = tag.color.rgbComponents
        return Color(red: r, green: g, blue: b)
    }

    private var textColor: Color {
        if isSelected {
            return colorScheme == .dark ? .white : .primary
        } else {
            return isHovering ? .primary : .secondary
        }
    }

    private var badgeTextColor: Color {
        if isSelected {
            return colorScheme == .dark ? .white.opacity(0.9) : .primary
        } else {
            return .secondary
        }
    }

    private var badgeBackgroundColor: Color {
        if isSelected {
            return tagColor.opacity(0.25)
        } else {
            return Color.secondary.opacity(0.12)
        }
    }

    private var chipBackground: some View {
        Capsule()
            .fill(isDropTarget ?
                tagColor.opacity(0.35) :  // Strong highlight when drop target
                (isSelected ?
                    tagColor.opacity(colorScheme == .dark ? 0.25 : 0.15) :
                    (isHovering ?
                        Color.primary.opacity(0.08) :
                        Color.primary.opacity(colorScheme == .light ? 0.04 : 0.08))))
    }

    private var chipBorder: some View {
        Capsule()
            .stroke(
                isDropTarget ?
                    tagColor.opacity(0.8) :  // Strong border when drop target
                    (isSelected ?
                        tagColor.opacity(colorScheme == .dark ? 0.5 : 0.4) :
                        (isHovering ?
                            Color.primary.opacity(0.2) :
                            Color.primary.opacity(0.1))),
                lineWidth: isDropTarget ? 2.5 : (isSelected ? 1.5 : 0.5)
            )
    }

    // MARK: - Color Change Methods

    func openColorPicker() {
        NSLog("🎨 Opening color picker for tag: \(tag.name)")
        selectedColorForEdit = tag.color
        showColorPicker = true
    }

    private func handleColorChange(_ newColor: TagColor) {
        NSLog("🎨 Color changed to \(newColor.displayName) for tag: \(tag.name)")
        onColorChange?(newColor)
        showColorPicker = false
    }

    // MARK: - Inline Rename Methods

    private func startRename() {
        NSLog("✏️ RENAME: Starting inline rename for '\(tag.name)'")
        editingName = tag.name
        isRenaming = true
        isTextFieldFocused = true
    }

    private func saveRename() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != tag.name else {
            cancelRename()
            return
        }

        let oldName = displayName
        NSLog("✅ RENAME: Saving new name '\(trimmed)' for tag '\(tag.name)'")

        // Optimistically update the UI immediately
        displayName = trimmed

        // Call the rename handler with completion callback
        onRename?(trimmed) { success in
            if success {
                // Success: exit rename mode
                isRenaming = false
                NSLog("✅ RENAME: Successfully renamed to '\(trimmed)'")
            } else {
                // Failure: revert to old name and exit rename mode
                displayName = oldName
                isRenaming = false
                NSLog("❌ RENAME: Failed to rename, reverted to '\(oldName)'")
            }
        }
    }

    private func cancelRename() {
        NSLog("❌ RENAME: Cancelled rename for '\(tag.name)'")
        isRenaming = false
        editingName = ""
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        // Unselected
        TagChipView(
            tag: Tag(name: "Work", color: .blue),
            itemCount: 5,
            isSelected: false,
            onTap: {}
        )

        // Selected
        TagChipView(
            tag: Tag(name: "Important", color: .red),
            itemCount: 12,
            isSelected: true,
            onTap: {}
        )

        // No count
        TagChipView(
            tag: Tag(name: "Ideas", color: .yellow),
            itemCount: 0,
            isSelected: false,
            onTap: {}
        )

        // Various colors
        HStack {
            ForEach([TagColor.red, TagColor.orange, TagColor.green, TagColor.purple], id: \.self) { color in
                TagChipView(
                    tag: Tag(name: color.displayName, color: color),
                    itemCount: Int.random(in: 1...20),
                    isSelected: false,
                    onTap: {}
                )
            }
        }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
