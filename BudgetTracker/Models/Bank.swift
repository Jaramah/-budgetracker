import Foundation
import SwiftUI

/// The credit-card issuing banks we can recognise from a statement's text/filename.
/// Used to route an uploaded statement to the correct `CreditCardAccount`.
///
/// Detection is heuristic and confirmed by the user on the Review screen — we never
/// silently trust a guess (matches the app's "reconcile, don't guess" rule).
enum Bank: String, CaseIterable, Identifiable, Codable {
    case dbs
    case ocbc
    case uob
    case standardChartered
    case trust
    case citibank
    case hsbc
    case maybank
    case amex
    case unknown

    var id: String { rawValue }

    /// Human label shown in pickers and the Cards screen.
    var label: String {
        switch self {
        case .dbs:               return "DBS"
        case .ocbc:              return "OCBC"
        case .uob:               return "UOB"
        case .standardChartered: return "Standard Chartered"
        case .trust:             return "Trust"
        case .citibank:          return "Citibank"
        case .hsbc:              return "HSBC"
        case .maybank:           return "Maybank"
        case .amex:              return "American Express"
        case .unknown:           return "Other"
        }
    }

    /// Lower-cased keywords that, if found in statement text or the file name,
    /// indicate this issuer. Order matters: longer / more specific first.
    var keywords: [String] {
        switch self {
        case .dbs:               return ["dbs", "posb"]
        case .ocbc:              return ["ocbc", "oversea-chinese"]
        case .uob:               return ["uob", "united overseas bank"]
        case .standardChartered: return ["standard chartered", "stanchart", "sc.com", "standardchartered"]
        case .trust:             return ["trust bank", "trustbank", "trust.sg", "trust "]
        case .citibank:          return ["citibank", "citi ", "citigroup"]
        case .hsbc:              return ["hsbc"]
        case .maybank:           return ["maybank"]
        case .amex:              return ["american express", "amex"]
        case .unknown:           return []
        }
    }

    /// A representative accent colour for the issuer (used on card chips).
    var tintHex: String {
        switch self {
        case .dbs:               return "#D0021B"
        case .ocbc:              return "#E4002B"
        case .uob:               return "#005EB8"
        case .standardChartered: return "#0473EA"
        case .trust:             return "#111111"
        case .citibank:          return "#003B70"
        case .hsbc:              return "#DB0011"
        case .maybank:           return "#FFC72C"
        case .amex:              return "#2E77BC"
        case .unknown:           return "#E8B339"
        }
    }
}
