import SwiftUI

/// Design system for the "Aurora" theme — a dark fintech look matching the
/// reference: near-black background, elevated glass cards with hairline white
/// borders, a blue primary accent, and big bold money figures as the hero.
enum DS {
    // MARK: Backgrounds
    static let bgBase     = Color(hex: "#05060A")   // page background (near-black)
    static let bgCard     = Color(hex: "#111420")   // elevated card
    static let bgCardHi   = Color(hex: "#171B2B")   // higher elevation / pressed
    static let hairline   = Color.white.opacity(0.08)
    static let hairlineHi  = Color.white.opacity(0.14)

    // MARK: Accents
    static let accent     = Color(hex: "#3B82F6")   // primary blue
    static let accentSoft = Color(hex: "#60A5FA")   // lighter blue
    static let accentDim  = Color(hex: "#3B82F6").opacity(0.18)

    // MARK: Money semantics
    static let moneyIn    = Color(hex: "#34D399")   // income / positive (green)
    static let moneyOut   = Color(hex: "#F87171")   // spend / negative (red)
    static let warning    = Color(hex: "#FBBF24")   // over budget / due soon (amber)

    // MARK: Text
    static let inkPrimary   = Color.white.opacity(0.95)
    static let inkSecondary = Color.white.opacity(0.70)
    static let inkTertiary  = Color.white.opacity(0.45)

    // MARK: Metrics
    static let corner: CGFloat = 18
    static let cardPadding: CGFloat = 16

    /// A palette to color category donut slices / chips when a category has no color.
    static let categoryPalette: [Color] = [
        Color(hex: "#3B82F6"), Color(hex: "#8B5CF6"), Color(hex: "#EC4899"),
        Color(hex: "#F59E0B"), Color(hex: "#10B981"), Color(hex: "#06B6D4"),
        Color(hex: "#F43F5E"), Color(hex: "#A3E635"), Color(hex: "#FB923C")
    ]
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
