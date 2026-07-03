import Foundation

/// All money in the app is stored as **integer minor units (cents)** to avoid
/// floating-point drift — critical for reconciliation, where Double math would
/// produce phantom "differences". Convert to/from display strings only at the edges.
enum Money {
    /// The user's currency code (ISO 4217), defaults to SGD.
    static var code: String {
        UserDefaults.standard.string(forKey: "currencyCode") ?? "SGD"
    }

    /// Number of minor-unit digits for the current currency (2 for SGD/USD, 0 for JPY).
    static var fractionDigits: Int {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        return f.maximumFractionDigits
    }

    private static func formatter() -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        return f
    }

    /// Format cents as a currency string, e.g. 5230 -> "$52.30".
    static func string(_ cents: Int) -> String {
        let f = formatter()
        let divisor = pow(10.0, Double(f.maximumFractionDigits))
        let value = Double(cents) / divisor
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Signed string: "-$52.30" for expense, "+$52.30" for income. `cents` is magnitude.
    static func signedString(_ cents: Int, isExpense: Bool) -> String {
        (isExpense ? "-" : "+") + string(abs(cents))
    }

    /// The currency symbol alone, e.g. "$".
    static var symbol: String {
        formatter().currencySymbol ?? "$"
    }

    /// Parse user-typed input ("52.30", "1,234.5", "52") into cents. nil if unparseable.
    static func cents(from text: String) -> Int? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted)
            .joined()
        guard let value = Double(cleaned) else { return nil }
        let divisor = pow(10.0, Double(fractionDigits))
        return Int((value * divisor).rounded())
    }

    /// Convert a Double amount (e.g. from a parser) into cents safely.
    static func centsFromDouble(_ value: Double) -> Int {
        let divisor = pow(10.0, Double(fractionDigits))
        return Int((value * divisor).rounded())
    }

    /// Alias for `cents(from:)` — parse typed input into cents. nil if unparseable.
    static func centsFromString(_ text: String) -> Int? { cents(from: text) }

    /// Plain (non-currency) numeric string for editable fields, e.g. 523045 -> "5230.45".
    static func plainString(_ cents: Int) -> String {
        let divisor = pow(10.0, Double(fractionDigits))
        let value = Double(cents) / divisor
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ""
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
