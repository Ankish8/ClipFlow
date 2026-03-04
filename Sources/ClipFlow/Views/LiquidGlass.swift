import SwiftUI
import ClipFlowCore

// MARK: - Liquid Glass View Modifiers

extension View {

    /// Rounded-rect glass card. Uses `.regular.interactive()` on macOS 26+,
    /// selected state adds a customAccent tint. Falls through on earlier OS.
    @ViewBuilder
    func glassCard(isSelected: Bool = false, cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(
                isSelected
                    ? .regular.tint(Color.customAccent.opacity(0.14)).interactive()
                    : .regular.interactive(),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            self
        }
    }

    /// Capsule glass chip with optional colour tint. Falls through on earlier OS.
    @ViewBuilder
    func glassChip(tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
            } else {
                self.glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            self
        }
    }

    /// Rounded-rect glass for toolbar / search inputs. Falls through on earlier OS.
    @ViewBuilder
    func glassControl(cornerRadius: CGFloat = 8) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
        }
    }

    /// Full overlay panel surface.
    /// macOS 26+: native Liquid Glass — truly transparent, samples real content behind the window.
    /// macOS < 26: clips to shape only (NSVisualEffectView in background provides frosted blur).
    @ViewBuilder
    func overlayPanel(cornerRadius: CGFloat = 32) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
