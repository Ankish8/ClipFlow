import SwiftUI
import ClipFlowCore
import UniformTypeIdentifiers

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
    @Environment(\.colorScheme) private var colorScheme

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
        Button(action: {
            if !isRenaming { onTap() }
        }) {
            HStack(spacing: 6) {
                // Tag color indicator - clickable to open color picker
                Circle()
                    .fill(tagColor)
                    .frame(width: 10, height: 10)
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
                        .foregroundStyle(.primary)
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
                        .onTapGesture(count: 2) {
                            startRename()
                        }
                }

                // Item count badge (if > 0)
                if itemCount > 0 && !isRenaming {
                    Text("\(itemCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                        )
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
        }
        .buttonStyle(.toolbarChip(isSelected: isSelected || isDropTarget, tint: tagColor))
        // Drop target: scale up + colored ring so the user clearly sees the assignment target
        .scaleEffect(isDropTarget ? 1.1 : 1.0)
        .overlay {
            if isDropTarget {
                Capsule()
                    .stroke(tagColor, lineWidth: 2)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tagColor)
                            .background(Circle().fill(.background))
                            .offset(x: 6, y: -6)
                    }
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.65), value: isDropTarget)
        .overlay {
            // AppKit NSDraggingDestination overlay — replaces SwiftUI .onDrop.
            // SwiftUI .onDrop reads drag data via NSItemProvider.loadDataRepresentation
            // (async), which can silently fail when the data was written synchronously
            // by beginDraggingSession / NSPasteboardItem in AppKitCardDragOverlay.
            // Reading NSDraggingInfo.draggingPasteboard directly (sync) is reliable.
            TagDropOverlay(onDrop: onDrop, isDropTarget: $isDropTarget)
        }
        .help(tag.name)
        .onChange(of: tag.name) { _, newName in
            // Sync displayName when tag is updated from parent
            if !isRenaming {
                displayName = newName
            }
        }
    }

    private var tagColor: Color { tag.color.swiftUIColor }

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

// MARK: - AppKit Drop Target

/// Transparent NSViewRepresentable that implements NSDraggingDestination.
///
/// SwiftUI's .onDrop wraps AppKit drag events through NSItemProvider,
/// which uses an async `loadDataRepresentation` call. When the data was
/// written synchronously via NSPasteboardItem / beginDraggingSession
/// (as AppKitCardDragOverlay does), the async bridge can silently drop
/// the data. Reading NSDraggingInfo.draggingPasteboard directly — the
/// same synchronous pasteboard AppKit populates during the session — is
/// always reliable. hitTest returns nil so mouse events pass through to
/// the SwiftUI button layer beneath.
private struct TagDropOverlay: NSViewRepresentable {
    let onDrop: ((UUID) -> Void)?
    @Binding var isDropTarget: Bool

    private static let dragType = NSPasteboard.PasteboardType(UTType.clipboardItemID.identifier)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TagDropView {
        let v = TagDropView()
        v.coordinator = context.coordinator
        v.registerForDraggedTypes([Self.dragType])
        return v
    }

    func updateNSView(_ v: TagDropView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: TagDropOverlay
        init(_ p: TagDropOverlay) { parent = p }
    }

    final class TagDropView: NSView {
        var coordinator: Coordinator?
        private static let dragType = NSPasteboard.PasteboardType(UTType.clipboardItemID.identifier)

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard sender.draggingPasteboard.availableType(from: [Self.dragType]) != nil else { return [] }
            DispatchQueue.main.async { self.coordinator?.parent.isDropTarget = true }
            return .copy
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            DispatchQueue.main.async { self.coordinator?.parent.isDropTarget = false }
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let data = sender.draggingPasteboard.data(forType: Self.dragType),
                  let uuidString = String(data: data, encoding: .utf8),
                  let itemId = UUID(uuidString: uuidString) else {
                NSLog("❌ TagDrop: failed to read UUID from pasteboard")
                DispatchQueue.main.async { self.coordinator?.parent.isDropTarget = false }
                return false
            }
            NSLog("✅ TagDrop: assigning item \(itemId)")
            DispatchQueue.main.async {
                self.coordinator?.parent.isDropTarget = false
                self.coordinator?.parent.onDrop?(itemId)
            }
            return true
        }

        override func concludeDragOperation(_ sender: NSDraggingInfo?) {
            DispatchQueue.main.async { self.coordinator?.parent.isDropTarget = false }
        }

        // Pass all mouse/keyboard events through to the SwiftUI layer beneath
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var acceptsFirstResponder: Bool { false }
        override var isOpaque: Bool { false }
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
