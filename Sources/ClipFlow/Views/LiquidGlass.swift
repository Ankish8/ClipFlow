import SwiftUI
import ClipFlowCore

// MARK: - Liquid Glass View Modifiers

extension View {

    /// Rounded-rect glass for toolbar / search inputs.
    func glassControl(cornerRadius: CGFloat = 8) -> some View {
        self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
    }

    /// Full-surface Liquid Glass panel.
    /// Drives live compositing via SwiftUI's Metal render pass — no key-window required.
    func overlayPanel(cornerRadius: CGFloat = 32) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

// MARK: - Toolbar Chip Button Style

/// Lightweight toolbar chip — no individual glass border, just a subtle capsule fill on hover/selection.
/// Designed for use inside a GlassEffectContainer where the backdrop is already established.
struct ToolbarChipButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    var tintColor: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, isSelected: isSelected, tintColor: tintColor)
    }

    private struct Inner: View {
        let configuration: ButtonStyle.Configuration
        let isSelected: Bool
        let tintColor: Color
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { isHovering = $0 }
        }

        private var fill: Color {
            if isSelected { return tintColor.opacity(0.20) }
            if configuration.isPressed { return .primary.opacity(0.14) }
            if isHovering { return .primary.opacity(0.10) }
            return .clear
        }
    }
}

extension ButtonStyle where Self == ToolbarChipButtonStyle {
    static func toolbarChip(isSelected: Bool = false, tint: Color = .primary) -> ToolbarChipButtonStyle {
        .init(isSelected: isSelected, tintColor: tint)
    }
}
