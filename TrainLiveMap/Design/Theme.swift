import SwiftUI
import UIKit

enum RailTheme {
    static let accent = Color(hex: "#f68b1e")
    static let darkBrown = Color(hex: "#1a1008")
    static let panelBrown = Color(hex: "#24170d")
    static let borderBrown = Color(hex: "#4a2f1a")
    static let cream = Color(hex: "#fff7ed")
    static let mutedCream = Color(hex: "#c7a98b")
    static let inboundBlue = Color(hex: "#2563eb")
    static let outboundOrange = Color(hex: "#b45309")
    static let communityPink = Color(hex: "#db2777")
}

enum RailFont {
    static let regularPostScriptName = "MPLUSRounded1c-Regular"
    static let boldPostScriptName = "MPLUSRounded1c-Bold"
    static let extraBoldPostScriptName = "MPLUSRounded1c-ExtraBold"

    static func regular(_ style: Font.TextStyle) -> Font {
        custom(regularPostScriptName, style: style)
    }

    static func bold(_ style: Font.TextStyle) -> Font {
        custom(boldPostScriptName, style: style)
    }

    static func extraBold(_ style: Font.TextStyle) -> Font {
        custom(extraBoldPostScriptName, style: style)
    }

    static var body: Font {
        regular(.body)
    }

    static func uiExtraBold(size: CGFloat) -> UIFont {
        uiFont(
            name: extraBoldPostScriptName,
            size: size,
            textStyle: .body,
            fallbackWeight: .heavy
        )
    }

    static func uiRegular(
        size: CGFloat,
        textStyle: UIFont.TextStyle = .body
    ) -> UIFont {
        uiFont(
            name: regularPostScriptName,
            size: size,
            textStyle: textStyle,
            fallbackWeight: .regular
        )
    }

    static func uiBold(
        size: CGFloat,
        textStyle: UIFont.TextStyle = .body
    ) -> UIFont {
        uiFont(
            name: boldPostScriptName,
            size: size,
            textStyle: textStyle,
            fallbackWeight: .bold
        )
    }

    private static func custom(
        _ name: String,
        style: Font.TextStyle
    ) -> Font {
        .custom(name, size: pointSize(for: style), relativeTo: style)
    }

    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .subheadline: 15
        case .callout: 16
        case .caption: 12
        case .caption2: 11
        case .footnote: 13
        default: 17
        }
    }

    private static func uiFont(
        name: String,
        size: CGFloat,
        textStyle: UIFont.TextStyle,
        fallbackWeight: UIFont.Weight
    ) -> UIFont {
        let base = UIFont(name: name, size: size)
            ?? .systemFont(ofSize: size, weight: fallbackWeight)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }
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

    func mplusAppTypography() -> some View {
        environment(\.font, RailFont.body)
    }

    func railControlBackground<S: Shape>(
        in shape: S
    ) -> some View {
        modifier(RailControlBackgroundModifier(shape: shape))
    }
}

private struct RailPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                backgroundColor,
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

    private var backgroundColor: Color {
        if reduceTransparency {
            return colorScheme == .dark
                ? RailTheme.panelBrown
                : Color(.systemBackground)
        }
        return colorScheme == .dark
            ? RailTheme.panelBrown.opacity(0.96)
            : Color(.systemBackground).opacity(0.96)
    }
}

private struct RailControlBackgroundModifier<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S

    func body(content: Content) -> some View {
        content.background(
            reduceTransparency
                ? (colorScheme == .dark ? RailTheme.panelBrown : .white)
                : Color(.systemBackground).opacity(0.94),
            in: shape
        )
    }
}
