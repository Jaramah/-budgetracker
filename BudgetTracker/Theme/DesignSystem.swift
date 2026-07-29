import SwiftUI

/// Design tokens for the current theme.
///
/// These were constants for a single hard-coded dark look. They are now computed
/// from `ThemeManager.shared.current`, so switching a theme repaints the whole app
/// without touching any of the 300-odd call sites that read `DS.something`.
///
/// Reading a static does not itself make SwiftUI re-render: a view only redraws
/// when something it observes changes. `RootView` observes `ThemeManager` and
/// re-identifies the screen subtree on change, which is what actually repaints.
enum DS {
    private static var t: Theme { ThemeManager.shared.current }

    // MARK: Backgrounds
    static var bgBase: Color     { Color(hex: t.bgBase) }
    static var bgCard: Color     { Color(hex: t.bgCard) }
    static var bgCardHi: Color   { Color(hex: t.bgCardHi) }
    static var hairline: Color   { Color(hex: t.hairline) }
    static var hairlineHi: Color { Color(hex: t.hairlineHi) }

    // MARK: Accents
    static var accent: Color     { Color(hex: t.accent) }
    static var accentSoft: Color { Color(hex: t.accentSoft) }
    static var accentDim: Color  { Color(hex: t.accent).opacity(0.18) }

    // MARK: Money semantics
    static var moneyIn: Color  { Color(hex: t.moneyIn) }
    static var moneyOut: Color { Color(hex: t.moneyOut) }
    static var warning: Color  { Color(hex: t.warning) }

    // MARK: Text
    static var inkPrimary: Color   { Color(hex: t.inkPrimary) }
    static var inkSecondary: Color { Color(hex: t.inkSecondary) }
    static var inkTertiary: Color  { Color(hex: t.inkTertiary) }

    // MARK: Metrics — shape is not themed, only colour.
    static let corner: CGFloat = 18
    static let cardPadding: CGFloat = 16

    /// A palette to color category donut slices / chips when a category has no color.
    static var categoryPalette: [Color] { t.categoryPalette.map { Color(hex: $0) } }
}

// MARK: - Color(hex:) — required by models (Category, CreditCardAccount) and theme.
extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: s).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch s.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 59, 130, 246) // fallback = accent blue
        }
        self.init(.sRGB,
                  red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Reusable card container
struct AuroraCard<Content: View>: View {
    var padding: CGFloat = DS.cardPadding
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.bgCard, in: RoundedRectangle(cornerRadius: DS.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.corner, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 1)
            )
    }
}

extension View {
    /// Standard screen background.
    func auroraBackground() -> some View {
        self.background(DS.bgBase.ignoresSafeArea())
    }
}
