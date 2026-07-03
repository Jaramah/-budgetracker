import Foundation

/// A small list of common currencies for the Settings picker.
/// (Money formatting now lives in `Money`, which is cents-based.)
struct CurrencyOption: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let label: String

    static let common: [CurrencyOption] = [
        .init(code: "SGD", label: "Singapore Dollar (S$)"),
        .init(code: "USD", label: "US Dollar ($)"),
        .init(code: "EUR", label: "Euro (€)"),
        .init(code: "GBP", label: "British Pound (£)"),
        .init(code: "JPY", label: "Japanese Yen (¥)"),
        .init(code: "AUD", label: "Australian Dollar (A$)"),
        .init(code: "MYR", label: "Malaysian Ringgit (RM)"),
        .init(code: "HKD", label: "Hong Kong Dollar (HK$)"),
        .init(code: "CNY", label: "Chinese Yuan (¥)"),
        .init(code: "INR", label: "Indian Rupee (₹)")
    ]
}
