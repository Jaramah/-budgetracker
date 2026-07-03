import Foundation
import SwiftUI

/// How a transaction was paid. Stored as a raw String on Transaction so SwiftData
/// persists it cleanly and we can add more methods later without a migration.
enum PaymentMethod: String, CaseIterable, Identifiable {
    case cash
    case credit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cash:   return "Cash"
        case .credit: return "Credit"
        }
    }

    var symbol: String {
        switch self {
        case .cash:   return "banknote.fill"
        case .credit: return "creditcard.fill"
        }
    }

    var color: Color {
        switch self {
        case .cash:   return .green
        case .credit: return .orange
        }
    }
}
