import SwiftUI
import ClipFlowCore

// MARK: - Liquid Glass View Modifiers

extension View {

    /// Rounded-rect glass for toolbar / search inputs.
    func glassControl(cornerRadius: CGFloat = 8) -> some View {
        self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
    }

    /// Subtle rounded input chrome for toolbar text fields.
    func toolbarInputShell(isError: Bool = false, cornerRadius: CGFloat = 12) -> some View {
        modifier(ToolbarInputShellModifier(isError: isError, cornerRadius: cornerRadius))
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
    var forceHover: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        Inner(
            configuration: configuration,
            isSelected: isSelected,
            tintColor: tintColor,
            forceHover: forceHover
        )
    }

    private struct Inner: View {
        let configuration: ButtonStyle.Configuration
        let isSelected: Bool
        let tintColor: Color
        let forceHover: Bool
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
            if isHovering || forceHover { return .primary.opacity(0.10) }
            return .clear
        }
    }
}

extension ButtonStyle where Self == ToolbarChipButtonStyle {
    static func toolbarChip(
        isSelected: Bool = false,
        tint: Color = .primary,
        forceHover: Bool = false
    ) -> ToolbarChipButtonStyle {
        .init(isSelected: isSelected, tintColor: tint, forceHover: forceHover)
    }
}

private struct ToolbarInputShellModifier: ViewModifier {
    let isError: Bool
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.055)
    }

    private var borderColor: Color {
        if isError {
            return Color.red.opacity(colorScheme == .dark ? 0.45 : 0.30)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.12)
    }
}
