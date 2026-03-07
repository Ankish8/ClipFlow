import SwiftUI
import ClipFlowCore
import UniformTypeIdentifiers

// MARK: - Tag Drop Coordinator (module-level singleton)

/// Coordinates drag-to-tag assignment via NSDraggingSource callbacks.
///
/// Each TagDropView registers itself (not its frame) here. During a drag,
/// Coordinator.draggingSession(_:movedTo:) calls tagId(at:) which computes
/// each view's screen frame LIVE from the current window position. This avoids
/// the stale-frame bug: if frames were stored at registration time the overlay
/// window is still at its off-screen initial position (below the visible area),
/// so every lookup during the actual drag would return nil.
@MainActor
final class TagDropCoordinator: ObservableObject {
    static let shared = TagDropCoordinator()

    /// The tag currently under the drag cursor, or nil.
    @Published var hoveredTagId: UUID? = nil

    /// Weak references to TagDropView instances, keyed by tag ID.
    private var tagViews: [UUID: WeakNSView] = [:]

    /// Called when the user drops a card onto a tag. (itemId, tagId)
    var onTagApplied: ((UUID, UUID) -> Void)? = nil

    func register(view: NSView, tagId: UUID) {
        tagViews[tagId] = WeakNSView(view)
    }

    func unregister(tagId: UUID) {
        tagViews.removeValue(forKey: tagId)
    }

    /// Computes each tag chip's screen frame live so window animation never
    /// causes stale coordinates. Called on every drag-move event.
    func tagId(at screenPoint: NSPoint) -> UUID? {
        tagViews.first { _, ref in
            guard let v = ref.value, let w = v.window else { return false }
            let screenFrame = w.convertToScreen(v.convert(v.bounds, to: nil))
            return screenFrame.contains(screenPoint)
        }?.key
    }
}

/// Weak wrapper so TagDropCoordinator doesn't retain NSView instances.
private final class WeakNSView {
    weak var value: NSView?
    init(_ v: NSView) { value = v }
}

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
    @ObservedObject private var dropCoordinator = TagDropCoordinator.shared
    private var isActiveDrop: Bool {
        isDropTarget || dropCoordinator.hoveredTagId == tag.id
    }

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
        .buttonStyle(.toolbarChip(isSelected: isSelected || isActiveDrop, tint: tagColor))
        // Drop target: scale up + colored ring so the user clearly sees the assignment target
        .scaleEffect(isActiveDrop ? 1.1 : 1.0)
        .overlay {
            if isActiveDrop {
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
        .animation(.spring(response: 0.2, dampingFraction: 0.65), value: isActiveDrop)
        .overlay {
            // AppKit NSDraggingDestination overlay — replaces SwiftUI .onDrop.
            // SwiftUI .onDrop reads drag data via NSItemProvider.loadDataRepresentation
            // (async), which can silently fail when the data was written synchronously
            // by beginDraggingSession / NSPasteboardItem in AppKitCardDragOverlay.
            // Reading NSDraggingInfo.draggingPasteboard directly (sync) is reliable.
            // tagId is passed so TagDropView can register its screen frame with
            // TagDropCoordinator — enabling coordinate-based drop detection that
            // bypasses GlassEffectContainer view-hierarchy routing failures.
            TagDropOverlay(tagId: tag.id, onDrop: onDrop, isDropTarget: $isDropTarget)
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
    let tagId: UUID
    let onDrop: ((UUID) -> Void)?
    @Binding var isDropTarget: Bool

    private static let dragType = NSPasteboard.PasteboardType(UTType.clipboardItemID.identifier)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TagDropView {
        let v = TagDropView()
        v.coordinator = context.coordinator
        v.tagId = tagId
        v.registerForDraggedTypes([Self.dragType])
        return v
    }

    func updateNSView(_ v: TagDropView, context: Context) {
        context.coordinator.parent = self
        v.tagId = tagId
    }

    final class Coordinator: NSObject {
        var parent: TagDropOverlay
        init(_ p: TagDropOverlay) { parent = p }
    }

    final class TagDropView: NSView {
        var coordinator: Coordinator?
        var tagId: UUID = UUID()
        private static let dragType = NSPasteboard.PasteboardType(UTType.clipboardItemID.identifier)

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Register/unregister the VIEW (not its frame) so TagDropCoordinator
            // can compute the screen frame live during a drag. Storing the frame
            // here would be stale: the overlay window is still at its off-screen
            // initial position when this fires, before the slide-up animation.
            if window != nil {
                TagDropCoordinator.shared.register(view: self, tagId: tagId)
            } else {
                TagDropCoordinator.shared.unregister(tagId: tagId)
            }
        }

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

        // hitTest returns nil so all mouse events pass through to the SwiftUI button
        // layer beneath. TagDropView sits in its own NSHostingView (AppKitCardDragOverlay)
        // which is a SIBLING of the card-content NSHostingView — NOT a descendant of it.
        // Therefore the card-content NSHostingView's NSGestureRecognizers never see events
        // consumed by TagDropView; returning nil is the only way to let button taps reach
        // the sibling hosting view that actually holds the SwiftUI button.
        // Drop detection is handled by TagDropCoordinator (coordinate-based, no hitTest needed).
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
