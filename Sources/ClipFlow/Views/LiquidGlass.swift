import SwiftUI
import ClipFlowCore

// MARK: - Liquid Glass View Modifiers

extension View {

    /// Rounded-rect glass card using Liquid Glass with interactive highlight.
    /// Selected state adds a customAccent tint.
    func glassCard(isSelected: Bool = false, cornerRadius: CGFloat = 12) -> some View {
        self.glassEffect(
            isSelected
                ? .regular.tint(Color.customAccent.opacity(0.14)).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: cornerRadius)
        )
    }

    /// Capsule glass chip with optional colour tint.
    @ViewBuilder
    func glassChip(tint: Color? = nil) -> some View {
        if let tint {
            self.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
        } else {
            self.glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    /// Rounded-rect glass for toolbar / search inputs.
    func glassControl(cornerRadius: CGFloat = 8) -> some View {
        self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
    }

    /// Full overlay panel surface with native Liquid Glass.
    func overlayPanel(cornerRadius: CGFloat = 32) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
