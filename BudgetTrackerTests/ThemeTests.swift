import XCTest
import SwiftUI
@testable import BudgetTracker

/// Themes are plain data, so the things that can silently break are structural:
/// a duplicate id, a typo'd hex string, or a light theme that kept white ink and
/// renders invisible. These catch all three without needing to render anything.
final class ThemeTests: XCTestCase {

    func testIDsAreUniqueAndResolvable() {
        let ids = Theme.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate theme id")
        for id in ids {
            XCTAssertEqual(Theme.named(id).id, id)
        }
    }

    /// An unknown id must fall back rather than crash — a stored preference can
    /// outlive the theme it names if one is ever removed.
    func testUnknownIDFallsBackToAurora() {
        XCTAssertEqual(Theme.named("no-such-theme").id, Theme.aurora.id)
        XCTAssertEqual(Theme.named("").id, Theme.aurora.id)
    }

    /// Every colour must be a well-formed hex string. `Color(hex:)` silently
    /// returns accent blue for anything it can't parse, so a typo would show up
    /// as a mysteriously blue swatch rather than an error.
    func testEveryColourIsWellFormedHex() {
        let pattern = "^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"
        for t in Theme.all {
            var all = [t.bgBase, t.bgCard, t.bgCardHi, t.hairline, t.hairlineHi,
                       t.accent, t.accentSoft, t.moneyIn, t.moneyOut, t.warning,
                       t.inkPrimary, t.inkSecondary, t.inkTertiary]
            all.append(contentsOf: t.categoryPalette)
            for hex in all {
                XCTAssertNotNil(hex.range(of: pattern, options: .regularExpression),
                                "\(t.name): malformed hex \(hex)")
            }
        }
    }

    func testCategoryPalettesAreCompleteAndDistinct() {
        for t in Theme.all {
            XCTAssertGreaterThanOrEqual(t.categoryPalette.count, 9,
                                        "\(t.name): needs at least 9 category colours")
            XCTAssertEqual(Set(t.categoryPalette).count, t.categoryPalette.count,
                           "\(t.name): duplicate category colour")
        }
    }

    /// Ink must contrast with the page. Dark themes use light ink, light themes
    /// dark ink — reversing one makes text unreadable, which is easy to do when
    /// copying an existing theme as a starting point.
    func testInkContrastsWithBackground() {
        for t in Theme.all {
            let bg = luminance(t.bgBase)
            let ink = luminance(t.inkPrimary)
            if t.isDark {
                XCTAssertLessThan(bg, 0.3, "\(t.name): dark theme needs a dark background")
                XCTAssertGreaterThan(ink, 0.6, "\(t.name): dark theme needs light ink")
            } else {
                XCTAssertGreaterThan(bg, 0.7, "\(t.name): light theme needs a light background")
                XCTAssertLessThan(ink, 0.4, "\(t.name): light theme needs dark ink")
            }
        }
    }

    /// The default must stay Aurora so existing users don't get a surprise
    /// repaint on update.
    func testDefaultIsAurora() {
        XCTAssertEqual(Theme.all.first?.id, Theme.aurora.id)
    }

    // MARK: - Helpers

    /// Relative luminance of the RGB portion, ignoring any alpha prefix.
    private func luminance(_ hex: String) -> Double {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.count == 8 { s = String(s.dropFirst(2)) }   // drop alpha
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return 0 }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
