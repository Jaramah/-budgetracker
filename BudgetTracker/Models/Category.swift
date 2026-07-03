import Foundation
import SwiftData
import SwiftUI

/// A spending/income category, e.g. "Food", "Transport".
/// Holds its own optional monthly budget (in cents) for budget-vs-actual.
@Model
final class Category {
    var id: UUID
    var name: String
    /// SF Symbol name used as the icon, e.g. "fork.knife".
    var symbol: String
    /// Stored as a hex string so SwiftData persists it cleanly.
    var colorHex: String
    /// Monthly budget in cents. 0 means "no budget set".
    var monthlyBudgetCents: Int
    /// Sort order in lists.
    var sortIndex: Int

    /// Last local modification time, used for last-write-wins sync with the backend.
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "tag.fill",
        colorHex: String = "#E8B339",
        monthlyBudgetCents: Int = 0,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.monthlyBudgetCents = monthlyBudgetCents
        self.sortIndex = sortIndex
    }

    var color: Color { Color(hex: colorHex) }
}
