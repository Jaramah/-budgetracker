import Foundation
import SwiftData

/// Exports all transactions to a CSV file in the temporary directory and returns
/// its URL for the iOS share sheet. This is the user's backup / escape hatch
/// (addresses the "on-device only, no backup" risk).
enum CSVExporter {
    @MainActor
    static func exportTransactions(_ transactions: [Transaction]) -> URL? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = DateHelpers.calendar.timeZone

        func esc(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }

        var rows = ["Date,Description,Category,Type,PaymentMethod,Amount,Currency"]
        let sorted = transactions.sorted { $0.date < $1.date }
        for t in sorted {
            let amount = Money.string(t.amountCents)
                .replacingOccurrences(of: Money.symbol, with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
            let cols = [
                df.string(from: t.date),
                esc(t.note),
                esc(t.category?.name ?? "Uncategorized"),
                t.isExpense ? "Expense" : "Income",
                t.paymentMethod.label,
                (t.isExpense ? "-" : "") + amount,
                Money.code
            ]
            rows.append(cols.joined(separator: ","))
        }

        let csv = rows.joined(separator: "\n")
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Budget-Export-\(stamp).csv")
        do {
            try csv.data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
