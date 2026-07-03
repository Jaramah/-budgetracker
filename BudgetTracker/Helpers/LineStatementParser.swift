import Foundation
import PDFKit

/// Line-based PDF statement parser — the single parser for all supported banks
/// (DBS, OCBC, Standard Chartered, UOB, Trust — all validated on real statements).
///
/// Handles the four SG credit notations:
///   • `1,884.04 CR`  (DBS — standalone trailing CR token)
///   • `30.82CR`      (StanChart / UOB — CR suffix attached)
///   • `(352.00)`     (OCBC — parentheses)
///   • `+1,178.22`    (Trust — leading plus)
///
/// A transaction line starts with one or two dates and ends with a monetary
/// amount; the text between is the description. Wrapped merchant names that spill
/// onto the *next* line (Trust: "PLAYMADE - TAMPINES 1" / "SINGAPORE SG") are
/// captured as "orphan" lines and attached to the most recent transaction.
/// Date-led summary tables (instalment / points / cashback) are skipped.
enum LineStatementParser {

    private static let amount = try! NSRegularExpression(
        pattern: #"^\(?([+\-]?)([\d,]+\.\d{2})(CR|DR)?\)?$"#, options: [.caseInsensitive])
    private static let dayNum = try! NSRegularExpression(pattern: #"^\d{1,2}$"#)
    private static let monAbbr = try! NSRegularExpression(pattern: #"^[A-Za-z]{2,3}$"#)  // 2-3 letters (handles truncated "Ju", "Ma")
    private static let dateSlash = try! NSRegularExpression(pattern: #"^\d{1,2}/\d{1,2}(/\d{2,4})?$"#)

    private static let noise = [
        "previous balance", "new transactions", "sub-total", "sub total", "subtotal",
        "balance from previous", "new balance", "grand total", "last month",
        "minimum payment", "total balance for", "total amount due", "payment due",
        "statement", "description", "amount due", "card no", "total:", "total "
    ]
    private static let stopZone = [
        "instalment payment plan summary", "instalment plans summary", "instalment plan summary",
        "points summary", "cashback summary"
    ]
    private static let resumeZone = [
        "post trans description", "transaction posting", "transaction date description",
        "date description amount", "description amount"
    ]

    static func parse(url: URL) -> [StatementParser.ParsedLine] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var out: [StatementParser.ParsedLine] = []
        var skipping = false
        var lastOrphan: String? = nil

        for p in 0..<doc.pageCount {
            guard let text = doc.page(at: p)?.string else { continue }
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                let low = line.lowercased()

                if resumeZone.contains(where: { low.contains($0) }) { skipping = false; continue }
                if stopZone.contains(where: { low.contains($0) }) { skipping = true }
                if skipping || line.isEmpty { continue }

                switch classify(line) {
                case .transaction(var parsed):
                    // If the line had no inline description, adopt a pending orphan.
                    if parsed.desc == "Transaction", let o = lastOrphan { parsed.desc = o }
                    lastOrphan = nil
                    out.append(parsed)
                case .orphan(let text):
                    // A wrapped description fragment for the row above/below.
                    if let last = out.indices.last {
                        out[last].desc += " " + text
                    } else {
                        lastOrphan = text
                    }
                case .ignore:
                    break
                }
            }
        }
        return out
    }

    private enum LineKind {
        case transaction(StatementParser.ParsedLine)
        case orphan(String)
        case ignore
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func classify(_ line: String) -> LineKind {
        let low = line.lowercased()
        if noise.contains(where: { low.contains($0) }) { return .ignore }

        var tokens = line.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return .ignore }

        // Standalone trailing CR/DR (DBS).
        var trailingCredit = false
        if let last = tokens.last?.uppercased(), last == "CR" || last == "DR" {
            trailingCredit = (last == "CR")
            tokens.removeLast()
        }

        // Leading date column(s).
        var dateStrings: [String] = []
        var consumed = 0
        while consumed < tokens.count {
            let t = tokens[consumed]
            if matches(dateSlash, t) {
                dateStrings.append(t); consumed += 1
            } else if consumed + 1 < tokens.count,
                      matches(dayNum, t), matches(monAbbr, tokens[consumed + 1]) {
                dateStrings.append(t + " " + tokens[consumed + 1]); consumed += 2
            } else { break }
            if dateStrings.count == 2 { break }
        }

        guard let firstDate = dateStrings.first else {
            // No date → possibly a wrapped description fragment (orphan).
            // Only treat as orphan if it's text (not a number-y noise line).
            let firstChar = line.first.map { String($0) } ?? ""
            if line.count > 2, Int(firstChar) == nil,
               !low.contains("ref no"), !low.contains("transaction ref"),
               !low.contains(" = "), !low.contains("page ") {
                return .orphan(line)
            }
            return .ignore
        }

        // Rightmost monetary token.
        var cents: Int? = nil
        var amtIndex: Int? = nil
        var isCredit = false
        var j = tokens.count - 1
        while j >= consumed {
            if let (c, credit) = parseAmount(tokens[j]) {
                cents = c; amtIndex = j; isCredit = credit; break
            }
            j -= 1
        }
        guard let value = cents, let ai = amtIndex, ai >= consumed else { return .ignore }
        if trailingCredit { isCredit = true }
        
        // SKIP credits entirely — we only want debits (charges/expenses)
        guard !isCredit else { return .ignore }

        var desc = tokens[consumed..<ai].joined(separator: " ")
        desc = stripRefs(desc).trimmingCharacters(in: .whitespaces)
        let dlow = desc.lowercased()
        if !desc.isEmpty, noise.contains(where: { dlow.contains($0) }) { return .ignore }
        if desc.isEmpty { desc = "Transaction" }

        let date = StatementParser.parseDate(firstDate) ?? Date()
        return .transaction(StatementParser.ParsedLine(
            date: date, desc: desc, amountCents: value, lowConfidence: false))  // Always positive (debit)
    }

    private static func parseAmount(_ token: String) -> (Int, Bool)? {
        let r = NSRange(token.startIndex..., in: token)
        guard let m = amount.firstMatch(in: token, range: r) else { return nil }
        func grp(_ i: Int) -> String {
            guard let rr = Range(m.range(at: i), in: token) else { return "" }
            return String(token[rr])
        }
        let sign = grp(1)
        let num = grp(2).replacingOccurrences(of: ",", with: "")
        let suffix = grp(3).uppercased()
        guard let val = Double(num) else { return nil }
        let paren = token.hasPrefix("(") && token.hasSuffix(")")
        let credit = (sign == "+") || (suffix == "CR") || paren
        return (Int((val * 100).rounded()), credit)
    }

    private static func stripRefs(_ s: String) -> String {
        let patterns = [#"(?i)Transaction Ref\s*\w*"#, #"(?i)Ref No\.?\s*:?\s*\w*"#, #"(?i)REF NO:?\s*\w*"#]
        var out = s
        for p in patterns { out = out.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        return out
    }
}
