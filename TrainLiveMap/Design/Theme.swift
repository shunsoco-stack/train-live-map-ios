import SwiftUI

enum RailTheme {
    static let accent = Color(hex: "#f68b1e")
    static let darkBrown = Color(hex: "#1a1008")
    static let panelBrown = Color(hex: "#24170d")
    static let borderBrown = Color(hex: "#4a2f1a")
    static let cream = Color(hex: "#fff7ed")
    static let mutedCream = Color(hex: "#c7a98b")
}

extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        switch sanitized.count {
        case 3:
            self.init(
                red: Double((value >> 8) & 0xF) / 15,
                green: Double((value >> 4) & 0xF) / 15,
                blue: Double(value & 0xF) / 15
            )
        case 6:
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        default:
            self = .gray
        }
    }
}

extension View {
    func railPanel(cornerRadius: CGFloat = 16) -> some View {
        modifier(RailPanelModifier(cornerRadius: cornerRadius))
    }

    func minimumTapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

private struct RailPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                colorScheme == .dark
                    ? RailTheme.panelBrown.opacity(0.96)
                    : Color(.systemBackground).opacity(0.96),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? RailTheme.borderBrown
                            : Color(.separator).opacity(0.55),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
    }
}
