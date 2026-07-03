import Foundation
import SwiftData

/// A savings goal shown on the Accounts ▸ Goals screen (e.g. "Emergency Fund",
/// "New Laptop"). Money in integer cents (see `Money`).
@Model
final class Goal {
    var id: UUID
    var name: String
    var targetCents: Int
    var savedCents: Int
    var colorHex: String
    var symbol: String
    var sortIndex: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        targetCents: Int,
        savedCents: Int = 0,
        colorHex: String = "#3B82F6",
        symbol: String = "target",
        sortIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.targetCents = max(0, targetCents)
        self.savedCents = max(0, savedCents)
        self.colorHex = colorHex
        self.symbol = symbol
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    /// Progress 0...1.
    var progress: Double {
        guard targetCents > 0 else { return 0 }
        return min(1.0, Double(savedCents) / Double(targetCents))
    }

    var isComplete: Bool { savedCents >= targetCents && targetCents > 0 }
}
