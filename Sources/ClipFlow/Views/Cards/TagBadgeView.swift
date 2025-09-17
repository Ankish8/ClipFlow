import SwiftUI
import ClipFlowCore

struct TagBadgeView: View {
    let tagName: String
    let tagColor: String?
    let size: TagBadgeSize = .medium
    let isInteractive: Bool = false
    let onTap: (() -> Void)? = nil
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            onTap?()
        }) {
            HStack(spacing: 4) {
                Text(tagName)
                    .font(.system(size: fontSize, weight: .medium))
            }
            .foregroundColor(textColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(borderColor, lineWidth: borderWidth)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isInteractive ? 1.0 : 0.9)
        .scaleEffect(isInteractive ? 1.0 : 0.95)
    }
    
    // MARK: - Computed Properties
    
    private var fontSize: CGFloat {
        switch size {
        case .small: return 10
        case .medium: return 11
        case .large: return 12
        }
    }
    
    private var horizontalPadding: CGFloat {
        switch size {
        case .small: return 6
        case .medium: return 8
        case .large: return 10
        }
    }
    
    private var verticalPadding: CGFloat {
        switch size {
        case .small: return 2
        case .medium: return 3
        case .large: return 4
        }
    }
    
    private var cornerRadius: CGFloat {
        switch size {
        case .small: return 4
        case .medium: return 6
        case .large: return 8
        }
    }
    
    private var borderWidth: CGFloat {
        isInteractive ? 1.0 : 0.5
    }
    
    private var backgroundColor: Color {
        if let color = tagColor {
            return Color(hex: color).opacity(colorScheme == .light ? 0.15 : 0.25)
        } else {
            return colorScheme == .light ? Color.primary.opacity(0.08) : Color.primary.opacity(0.15)
        }
    }
    
    private var borderColor: Color {
        if let color = tagColor {
            return Color(hex: color).opacity(colorScheme == .light ? 0.3 : 0.5)
        } else {
            return colorScheme == .light ? Color.primary.opacity(0.2) : Color.primary.opacity(0.3)
        }
    }
    
    private var textColor: Color {
        if let color = tagColor {
            return Color(hex: color)
        } else {
            return colorScheme == .light ? Color.primary.opacity(0.8) : Color.primary.opacity(0.9)
        }
    }
}

enum TagBadgeSize {
    case small
    case medium
    case large
}

// Extension to create Color from hex string
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}