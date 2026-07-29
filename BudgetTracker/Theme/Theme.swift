import SwiftUI

/// A complete colour palette for the app.
///
/// Every colour is stored as a hex string — 6 digits for opaque, 8 for ARGB —
/// so a theme is plain data and can be persisted, diffed and unit-tested without
/// touching SwiftUI. `DS` reads whichever theme is current, which is why adding a
/// theme needs no changes in the 300-odd places views reference `DS`.
struct Theme: Identifiable, Hashable {
    let id: String
    let name: String
    /// One-line description shown under the name in the picker.
    let blurb: String
    /// Drives `preferredColorScheme` so system controls, keyboards and the status
    /// bar match the palette instead of staying dark.
    let isDark: Bool

    // Backgrounds
    let bgBase: String
    let bgCard: String
    let bgCardHi: String
    let hairline: String
    let hairlineHi: String

    // Accents
    let accent: String
    let accentSoft: String

    // Money semantics
    let moneyIn: String
    let moneyOut: String
    let warning: String

    // Text
    let inkPrimary: String
    let inkSecondary: String
    let inkTertiary: String

    // Category chips / donut slices
    let categoryPalette: [String]

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

extension Theme {

    /// The original look: near-black with a blue accent. Kept as the default so
    /// existing users see no change until they choose otherwise.
    static let aurora = Theme(
        id: "aurora", name: "Aurora",
        blurb: "Near-black with an electric blue accent",
        isDark: true,
        bgBase: "#05060A", bgCard: "#111420", bgCardHi: "#171B2B",
        hairline: "#14FFFFFF", hairlineHi: "#24FFFFFF",
        accent: "#3B82F6", accentSoft: "#60A5FA",
        moneyIn: "#34D399", moneyOut: "#F87171", warning: "#FBBF24",
        inkPrimary: "#F2FFFFFF", inkSecondary: "#B3FFFFFF", inkTertiary: "#73FFFFFF",
        categoryPalette: ["#3B82F6", "#8B5CF6", "#EC4899", "#F59E0B", "#10B981",
                          "#06B6D4", "#F43F5E", "#A3E635", "#FB923C"]
    )

    /// Deep indigo with violet. Softer than Aurora — less contrast, easier at night.
    static let midnight = Theme(
        id: "midnight", name: "Midnight",
        blurb: "Deep indigo with a violet accent",
        isDark: true,
        bgBase: "#0A0A1F", bgCard: "#16162E", bgCardHi: "#1E1E3D",
        hairline: "#1AFFFFFF", hairlineHi: "#2BFFFFFF",
        accent: "#8B5CF6", accentSoft: "#A78BFA",
        moneyIn: "#34D399", moneyOut: "#FB7185", warning: "#FBBF24",
        inkPrimary: "#F2FFFFFF", inkSecondary: "#B3FFFFFF", inkTertiary: "#73FFFFFF",
        categoryPalette: ["#8B5CF6", "#6366F1", "#EC4899", "#F59E0B", "#22D3EE",
                          "#34D399", "#FB7185", "#C084FC", "#FCD34D"]
    )

    /// Neutral greys with teal. No colour cast — the most "instrument panel" of
    /// the dark themes, and the easiest to read long lists of figures in.
    static let graphite = Theme(
        id: "graphite", name: "Graphite",
        blurb: "Neutral greys with a teal accent",
        isDark: true,
        bgBase: "#0D0F10", bgCard: "#191C1E", bgCardHi: "#22262A",
        hairline: "#17FFFFFF", hairlineHi: "#26FFFFFF",
        accent: "#14B8A6", accentSoft: "#2DD4BF",
        moneyIn: "#4ADE80", moneyOut: "#F87171", warning: "#FACC15",
        inkPrimary: "#F2FFFFFF", inkSecondary: "#B3FFFFFF", inkTertiary: "#73FFFFFF",
        categoryPalette: ["#14B8A6", "#38BDF8", "#A78BFA", "#FACC15", "#4ADE80",
                          "#F87171", "#FB923C", "#E879F9", "#94A3B8"]
    )

    /// Light theme. The app was hard-coded to dark before this existed, so this is
    /// the one that most changes who can comfortably use it — in daylight, and for
    /// anyone who finds white-on-black text hard to read.
    static let daylight = Theme(
        id: "daylight", name: "Daylight",
        blurb: "Clean white with a deep blue accent",
        isDark: false,
        bgBase: "#F4F6FA", bgCard: "#FFFFFF", bgCardHi: "#EDF1F7",
        hairline: "#1A0F172A", hairlineHi: "#2E0F172A",
        accent: "#2563EB", accentSoft: "#3B82F6",
        // Darker than the dark-theme equivalents: #34D399 on white fails contrast.
        moneyIn: "#047857", moneyOut: "#DC2626", warning: "#B45309",
        inkPrimary: "#E60F172A", inkSecondary: "#A60F172A", inkTertiary: "#6B0F172A",
        categoryPalette: ["#2563EB", "#7C3AED", "#DB2777", "#D97706", "#059669",
                          "#0891B2", "#E11D48", "#65A30D", "#EA580C"]
    )

    /// Warm light theme — paper and terracotta. Same readability benefits as
    /// Daylight without the clinical feel.
    static let sandstone = Theme(
        id: "sandstone", name: "Sandstone",
        blurb: "Warm paper with a terracotta accent",
        isDark: false,
        bgBase: "#FAF6F0", bgCard: "#FFFFFF", bgCardHi: "#F3ECE2",
        hairline: "#1F44403C", hairlineHi: "#3344403C",
        accent: "#C2410C", accentSoft: "#EA580C",
        moneyIn: "#15803D", moneyOut: "#B91C1C", warning: "#A16207",
        inkPrimary: "#E62A211A", inkSecondary: "#A62A211A", inkTertiary: "#6B2A211A",
        categoryPalette: ["#C2410C", "#B45309", "#4D7C0F", "#0F766E", "#7C2D12",
                          "#A16207", "#9F1239", "#3F6212", "#78350F"]
    )

    /// Order shown in Settings.
    static let all: [Theme] = [.aurora, .midnight, .graphite, .daylight, .sandstone]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .aurora
    }
}

/// Holds the active theme and persists the choice.
///
/// A singleton because `DS` is a set of statics used from 300+ call sites and
/// threading an environment value through all of them would be a far larger and
/// riskier change than this feature warrants. Views observe it via
/// `@EnvironmentObject` where they need to re-render.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let key = "selectedThemeID"

    @Published private(set) var current: Theme

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key) ?? Theme.aurora.id
        current = Theme.named(saved)
    }

    func select(_ theme: Theme) {
        guard theme.id != current.id else { return }
        UserDefaults.standard.set(theme.id, forKey: Self.key)
        current = theme
    }
}

/// One row in the Settings theme picker.
///
/// The swatch renders in the *candidate* theme's colours rather than the active
/// one, so you can see what you're choosing before you commit to it.
struct ThemeOptionRow: View {
    let theme: Theme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                swatch
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.inkPrimary)
                    Text(theme.blurb)
                        .font(.caption)
                        .foregroundStyle(DS.inkTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? DS.accent : DS.inkTertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityHint(theme.blurb)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// A miniature of the theme: page background, a card on top, and the accent
    /// plus both money colours — the four things that actually change the feel.
    private var swatch: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(hex: theme.bgBase))
            .frame(width: 52, height: 40)
            .overlay(
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: theme.bgCard))
                        .frame(height: 12)
                    HStack(spacing: 3) {
                        Circle().fill(Color(hex: theme.accent)).frame(width: 8, height: 8)
                        Circle().fill(Color(hex: theme.moneyIn)).frame(width: 8, height: 8)
                        Circle().fill(Color(hex: theme.moneyOut)).frame(width: 8, height: 8)
                    }
                }
                .padding(6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? DS.accent : DS.hairline,
                                  lineWidth: isSelected ? 2 : 1)
            )
    }
}
