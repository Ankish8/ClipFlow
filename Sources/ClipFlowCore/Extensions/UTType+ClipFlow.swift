import Foundation
import UniformTypeIdentifiers

// MARK: - ClipFlow Custom UTTypes

extension UTType {
    /// Custom UTType for ClipFlow clipboard item IDs
    /// This allows drag-and-drop to distinguish between:
    /// - Dragging for tagging (uses this custom type)
    /// - Dragging for pasting (uses standard content types)
    public static let clipboardItemID = UTType(exportedAs: "com.clipflow.clipboard-item-id")
}
