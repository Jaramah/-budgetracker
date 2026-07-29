import Foundation
import PDFKit

/// Parses uploaded credit-card statements into `[ParsedLine]`.
///
/// Design note (important, honest): bank statement layouts are NOT standardized.
/// - **CSV** export (which every major bank offers in online banking) is reliable —
///   we detect the date/description/amount columns heuristically.
/// - **PDF** is *best-effort*: we extract the text layer and scan for lines that
///   look like "DATE  DESCRIPTION  AMOUNT". Scanned/image-only PDFs won't yield text.
///
/// Either way, the user reviews every parsed line on the import screen before it's
/// saved — nothing is trusted blindly.
enum StatementParser {

    struct ParsedLine: Identifiable {
        let id = UUID()
        var date: Date
        var desc: String
        /// Positive = charge (spend); negative = payment/refund/credit. In cents.
        var amountCents: Int
        /// Whether we're confident about this row (used to flag for review).
        var lowConfidence: Bool = false
        /// Auto-assigned category (set on the review screen), user can override.
        var categoryID: UUID? = nil
        /// ISO code of the currency actually charged, when the statement shows a
        /// foreign transaction. `amountCents` stays in the card's own currency —
        /// this is what the merchant billed before conversion.
        var foreignCurrency: String? = nil
        /// The original amount in minor units of `foreignCurrency`.
        var foreignAmountCents: Int? = nil
    }

    enum ParseError: LocalizedError {
        case unsupported
        case noTextInPDF
        case nothingFound
        case locked

        var errorDescription: String? {
            switch self {
            case .unsupported:  return "Unsupported file. Please upload your bank's PDF statement."
            case .noTextInPDF:  return "This PDF has no readable text — it looks like a scan or photo of a statement. Download the original PDF statement from your bank's app/website (not a scan) and upload that."
            case .nothingFound: return "Couldn't find any transactions in this PDF statement. If it's a genuine statement PDF, please share it so the parser can be tuned for this layout — or add the transactions manually."
            case .locked:       return "This PDF is password-protected. Open it in the Files app, enter the password, save an unlocked copy (Share ▸ Print ▸ Save as PDF), then upload that."
            }
        }
    }

    // MARK: Entry point

    /// Everything an import needs to know, not just the rows.
    struct ParseResult {
        var lines: [ParsedLine]
        /// Dates the statement printed about itself.
        var meta = StatementMeta()
        /// The total the bank footed its column with, if it printed one.
        var declaredTotalCents: Int?
        /// Whether the parsed debits add up to that total. `nil` when there was no
        /// total to check against — which is not the same as "balanced", and the
        /// review screen distinguishes the two.
        var reconciled: Bool?
    }

    /// Convenience wrapper for callers that only want the rows.
    static func parse(url: URL) throws -> [ParsedLine] {
        try parseDetailed(url: url).lines
    }

    static func parseDetailed(url: URL) throws -> ParseResult {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "csv", "txt":
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = parseCSV(text)
            if lines.isEmpty { throw ParseError.nothingFound }
            // CSV exports carry transactions only — no statement header, so there
            // are no dates or totals to recover.
            return ParseResult(lines: lines)
        case "pdf":
            guard let doc = PDFDocument(url: url) else { throw ParseError.unsupported }
            // Password-protected statements (common for bank PDFs) can't be read.
            if doc.isLocked { throw ParseError.locked }
            let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ParseError.noTextInPDF
            }
            // Two complementary strategies — run both and keep the better result:
            //  • Coordinate parser rebuilds the visual table from glyph positions
            //    (needed when the text layer is column-scrambled).
            //  • Line parser reads the ordered text layer (better for the many banks
            //    whose PDF text is already clean, e.g. DBS/UOB/Trust).
            // Neither wins universally, so score each and pick the stronger.
            let coord = CoordinateStatementParser.parse(url: url)
            let lines = LineStatementParser.parse(url: url)
            // Third strategy: the "trailing amount block" layout (UOB), where amounts
            // are batched after the transactions rather than inline. Returns [] unless
            // that layout is detected, so it only wins for statements shaped that way.
            let block = LineStatementParser.parseBlock(url: url)
            // Selection is in two rounds. `score` only ever looked at *descriptions*,
            // so a parser could emit perfect merchant names against completely wrong
            // amounts and still win — which is exactly how UOB shipped mispaired rows.
            // Round 1 therefore keeps only the candidates whose debits reconcile with
            // the total the bank itself printed; round 2 falls back to the old
            // description score when the statement gives us nothing to check against.
            let declared = declaredTotalCents(in: text)
            let candidates = [lines, coord, block].filter { !$0.isEmpty }
            let reconciledPool = candidates.filter { reconciles($0, declared: declared) }
            let pool = reconciledPool.isEmpty ? candidates : reconciledPool
            let meta = statementMeta(in: text)
            // Ties go to the earliest candidate, preserving the old preference order
            // (line parser first, then coord, then block).
            if let best = pool.max(by: { score($0) < score($1) }) {
                return ParseResult(lines: annotateForeignAmounts(best), meta: meta,
                                   declaredTotalCents: declared,
                                   reconciled: declared.map { _ in reconciles(best, declared: declared) })
            }
            // Fallback: naive single-line text scan for unusual layouts.
            let fallback = parsePDFText(text)
            if fallback.isEmpty { throw ParseError.nothingFound }
            return ParseResult(lines: annotateForeignAmounts(fallback), meta: meta,
                               declaredTotalCents: declared,
                               reconciled: declared.map { _ in reconciles(fallback, declared: declared) })
        default:
            throw ParseError.unsupported
        }
    }

    /// Quality score for a parse result. Rewards rows with a real merchant name and
    /// *penalises* rows whose "description" is just digits — a bare year, a card-number
    /// fragment ("5240 4030 0103"), etc. Those are the tell-tale of a column-scrambled
    /// coordinate parse, so this lets `parse` reject a parser that recovered *more* rows
    /// but only garbage in favour of the one that recovered fewer, usable ones.
    private static func score(_ lines: [ParsedLine]) -> Int {
        lines.reduce(0) { acc, l in
            let d = l.desc.trimmingCharacters(in: .whitespaces)
            if d == "Transaction" || d.isEmpty { return acc }            // placeholder: neutral
            // A real name has a run of ≥3 consecutive letters; digit-soup doesn't.
            let hasWord = d.range(of: #"\p{L}{3,}"#, options: .regularExpression) != nil
            return acc + (hasWord ? 2 : -1)
        }
    }

    // MARK: Statement metadata

    /// Dates a statement prints about itself.
    struct StatementMeta {
        /// The date the statement was issued ("Statement Date  19 JUL 2026").
        var statementDate: Date?
        /// The payment due date the bank printed ("Due Date  07 AUG 2026").
        ///
        /// Worth far more than a computed one: it is the bank's own answer, so it
        /// already accounts for weekends, holidays and the cycle rolling into the
        /// next month. Only fall back to `CreditCardAccount.dueDate(forStatementDate:)`
        /// when a statement doesn't print it.
        var dueDate: Date?
    }

    private static let statementDateLabels = ["statement date", "statement dated", "date of statement"]
    private static let dueDateLabels = ["payment due date", "due date", "payment due by", "pay by date"]

    /// Pull the statement and due dates out of a statement's text.
    ///
    /// Handles both shapes the text layer produces: label and value on one line
    /// (`-layout`-style extraction) and label and value on consecutive lines
    /// (PDFKit's stream order often splits them).
    static func statementMeta(in text: String) -> StatementMeta {
        let rows = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var meta = StatementMeta()

        func value(at i: Int, after label: String) -> Date? {
            let row = rows[i]
            // Search the original string case-insensitively: indices taken from a
            // lowercased copy are not valid in the original, and lowercasing can
            // change length for non-ASCII, so offsetting between them is unsound.
            if let r = row.range(of: label, options: .caseInsensitive) {
                if let d = firstDate(inText: String(row[r.upperBound...])) { return d }
            }
            // Otherwise the next couple of non-empty lines — PDFKit's stream order
            // routinely splits a label from its value.
            for j in (i + 1)...(i + 2) where rows.indices.contains(j) {
                if let d = firstDate(inText: rows[j]) { return d }
            }
            return nil
        }

        for (i, row) in rows.enumerated() {
            let low = row.lowercased()
            // Due date first: "payment due date" also contains "date", and checking
            // the statement label first would claim the row.
            if meta.dueDate == nil, let label = dueDateLabels.first(where: { low.contains($0) }) {
                meta.dueDate = value(at: i, after: label)
                continue
            }
            if meta.statementDate == nil,
               let label = statementDateLabels.first(where: { low.contains($0) }) {
                meta.statementDate = value(at: i, after: label)
            }
        }
        return meta
    }

    /// First date-shaped substring in a fragment of text, resolved to a `Date`.
    static func firstDate(inText s: String) -> Date? {
        let patterns = [
            #"\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4}"#,      // 19 JUL 2026
            #"[A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}"#,     // July 19, 2026
            #"\d{4}-\d{1,2}-\d{1,2}"#,                 // 2026-07-19
            #"\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}"#      // 19/07/2026
        ]
        for p in patterns {
            guard let r = s.range(of: p, options: .regularExpression) else { continue }
            if let d = parseDate(String(s[r])) { return d }
        }
        return nil
    }

    // MARK: Foreign currency

    /// ISO codes we accept in a description. A curated list rather than "any three
    /// capitals", so merchant words like "THE" or "GST" aren't read as currencies.
    private static let currencyCodes: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "AUD", "NZD", "CAD", "CHF", "CNY", "HKD",
        "TWD", "KRW", "SGD", "MYR", "THB", "IDR", "PHP", "VND", "INR", "AED",
        "SAR", "ZAR", "SEK", "NOK", "DKK", "MXN", "BRL", "TRY", "RUB", "PLN"
    ]

    /// A charge posted in a foreign currency.
    struct ForeignAmount {
        let code: String
        /// Original amount in minor units of `code`.
        let cents: Int
        /// The description with the currency fragment removed.
        let cleanedDescription: String
    }

    /// Move any foreign-currency fragment out of each description and into the
    /// dedicated fields. Rows without one are returned untouched.
    static func annotateForeignAmounts(_ lines: [ParsedLine]) -> [ParsedLine] {
        lines.map { line in
            guard let f = foreignAmount(in: line.desc) else { return line }
            var l = line
            l.desc = f.cleanedDescription
            l.foreignCurrency = f.code
            l.foreignAmountCents = f.cents
            return l
        }
    }

    /// Pull "USD 10.80" / "KRW 775,200.00" out of a description.
    ///
    /// The parsers fold this line into the merchant name, which is why rows read
    /// "KOREAN AIRLINES Seoul KRW 775,200.00". Keeping the original amount lets the
    /// app show what was actually charged abroad instead of only the converted SGD.
    static func foreignAmount(in desc: String) -> ForeignAmount? {
        let pattern = #"\b([A-Z]{3})\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(desc.startIndex..., in: desc)
        for m in re.matches(in: desc, range: range) {
            guard let cr = Range(m.range(at: 1), in: desc),
                  let ar = Range(m.range(at: 2), in: desc) else { continue }
            let code = String(desc[cr])
            guard currencyCodes.contains(code) else { continue }
            let raw = String(desc[ar]).replacingOccurrences(of: ",", with: "")
            guard let v = Double(raw) else { continue }
            var cleaned = desc
            if let whole = Range(m.range, in: desc) { cleaned.removeSubrange(whole) }
            cleaned = cleaned
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return ForeignAmount(code: code,
                                 cents: Money.centsFromDouble(v),
                                 cleanedDescription: cleaned.isEmpty ? desc : cleaned)
        }
        return nil
    }

    // MARK: Reconciliation

    /// Sum of the per-section totals the statement itself prints ("SUB TOTAL"), in
    /// cents — or `nil` when the statement prints none.
    ///
    /// This is the one piece of ground truth a bank hands us for free: whatever we
    /// parse, the debits have to add up to the figure the bank footed the column
    /// with. A parser can mis-associate every amount and still produce plausible
    /// rows (UOB's block layout did exactly that), but it cannot do so *and* hit
    /// the printed total.
    ///
    /// "TOTAL BALANCE FOR …" is deliberately ignored: it repeats the sub-total for
    /// single-section cards, and double-counting it would make every parse fail.
    static func declaredTotalCents(in text: String) -> Int? {
        let rows = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var total: Int? = nil
        // The figure can sit on the label's own line ("SUB TOTAL   2,406.52") or on a
        // following line when the text layer splits label from column. Allow a short
        // look-ahead rather than requiring one shape.
        var lookahead = 0

        for row in rows {
            let low = row.lowercased()
            if low.contains("sub total") || low.contains("sub-total") || low.contains("subtotal") {
                if let c = lastAmountCents(in: row) {
                    total = (total ?? 0) + c
                    lookahead = 0
                } else {
                    lookahead = 3
                }
                continue
            }
            if lookahead > 0 {
                if let c = lastAmountCents(in: row) {
                    total = (total ?? 0) + c
                    lookahead = 0
                } else {
                    lookahead -= 1
                }
            }
        }
        return total
    }

    /// Whether a candidate parse's debits add up to what the bank printed. Returns
    /// `true` when there's nothing to check against, so statements without a printed
    /// sub-total are never rejected — this can only ever *break* ties, not invent them.
    static func reconciles(_ lines: [ParsedLine], declared: Int?) -> Bool {
        guard let declared, declared > 0 else { return true }
        let debits = lines.filter { $0.amountCents > 0 }.reduce(0) { $0 + $1.amountCents }
        // A cent of slack absorbs half-up vs half-even rounding in the parsers.
        return abs(debits - declared) <= 1
    }

    /// Rightmost monetary token on a line, in cents; `nil` if there isn't one.
    /// Credits ("2,040.69 CR") are rejected — a sub-total is never a credit, and
    /// accepting one would let a payment row masquerade as the column total.
    private static func lastAmountCents(in line: String) -> Int? {
        let up = line.uppercased()
        guard !up.hasSuffix("CR") else { return nil }
        let tokens = line.split(separator: " ").map(String.init)
        for t in tokens.reversed() {
            guard t.range(of: #"^\(?[+\-]?[\d,]+\.\d{2}\)?$"#, options: .regularExpression) != nil,
                  let v = Double(t.replacingOccurrences(of: #"[^\d.]"#, with: "",
                                                       options: .regularExpression))
            else { continue }
            return Int((v * 100).rounded())
        }
        return nil
    }

    // MARK: CSV

    /// Which column holds what, resolved from the header row.
    struct CSVLayout {
        var date: Int?
        var desc: Int?
        /// Single signed amount column.
        var amount: Int?
        /// Separate debit / credit columns (Chase, Amex, several SG banks).
        var debit: Int?
        var credit: Int?
        /// Running balance — never a transaction amount, so it must be excluded.
        var balance: Int?

        var hasAmountSource: Bool { amount != nil || debit != nil || credit != nil }
    }

    /// Map a header row to columns by name.
    ///
    /// Naming a column beats guessing at it. The previous parser took the
    /// *rightmost* number on each row, and almost every bank exports
    /// `Date, Description, Amount, Balance` — so it imported running balances as
    /// if they were charges.
    static func csvLayout(header: [String]) -> CSVLayout? {
        var l = CSVLayout()
        var recognised = 0
        for (i, raw) in header.enumerated() {
            let h = raw.lowercased().trimmingCharacters(in: .whitespaces)
            guard !h.isEmpty else { continue }
            // Balance first: "closing balance" also contains no amount keyword,
            // but "available balance" must never be mistaken for an amount.
            if h.contains("balance") {
                l.balance = l.balance ?? i; recognised += 1
            } else if h.contains("debit") || h.contains("withdrawal") || h.contains("paid out") {
                l.debit = l.debit ?? i; recognised += 1
            } else if h.contains("credit") || h.contains("deposit") || h.contains("paid in") {
                l.credit = l.credit ?? i; recognised += 1
            } else if h.contains("amount") || h.contains("value") {
                l.amount = l.amount ?? i; recognised += 1
            } else if h.contains("date") {
                // Prefer a transaction date over a posting date when both exist.
                if l.date == nil || h.contains("trans") { l.date = i }
                recognised += 1
            } else if h.contains("desc") || h.contains("detail") || h.contains("narrat")
                        || h.contains("particular") || h.contains("merchant")
                        || h.contains("reference") || h.contains("payee") {
                l.desc = l.desc ?? i; recognised += 1
            }
        }
        // Require a real header, not a data row that happened to contain a word.
        guard recognised >= 2, l.date != nil, l.hasAmountSource else { return nil }
        return l
    }

    /// CSV parser. Prefers a named header; falls back to positional heuristics
    /// only when the file has no usable header row.
    static func parseCSV(_ text: String) -> [ParsedLine] {
        let rawRows = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rawRows.isEmpty else { return [] }

        var rows = rawRows.map { splitCSVLine($0) }
        let layout = rows.first.flatMap { csvLayout(header: $0) }
        if layout != nil { rows.removeFirst() }
        else if let first = rows.first, firstAmount(in: first) == nil { rows.removeFirst() }

        // Day/month order is ambiguous in dd/MM vs MM/dd files. One value with a
        // first component above 12 settles it for the whole file, which is far more
        // reliable than a fixed global preference — that silently swapped every US
        // date where the day was 12 or lower.
        let order = detectDayMonthOrder(rows: rows, dateColumn: layout?.date)

        var result: [ParsedLine] = []
        for cols in rows {
            guard let (amount, isCredit) = csvAmount(cols, layout: layout) else { continue }
            // Credits are payments, refunds and salary — not spending. The PDF
            // parsers already exclude them; the CSV path used to import them as
            // positive charges, inflating every total.
            if isCredit { continue }

            let dateText = layout?.date.flatMap { cols.indices.contains($0) ? cols[$0] : nil }
            let date = dateText.flatMap { parseDate($0, order: order) }
                ?? firstDate(in: cols, order: order)
            let desc = csvDescription(cols, layout: layout)
            result.append(ParsedLine(date: date ?? Date(),
                                     desc: desc,
                                     amountCents: Money.centsFromDouble(abs(amount)),
                                     lowConfidence: date == nil))
        }
        return result
    }

    /// The charge for a row, and whether it is a credit.
    private static func csvAmount(_ cols: [String], layout: CSVLayout?) -> (Double, Bool)? {
        func value(_ i: Int?) -> Double? {
            guard let i, cols.indices.contains(i) else { return nil }
            return parseAmount(cols[i])
        }
        if let layout {
            // Separate debit/credit columns: whichever is populated wins.
            if layout.debit != nil || layout.credit != nil {
                if let d = value(layout.debit), d != 0 { return (d, false) }
                if let c = value(layout.credit), c != 0 { return (c, true) }
                return nil
            }
            guard let a = value(layout.amount) else { return nil }
            // A single signed column: negative conventionally means a credit, but
            // some banks sign the other way. Sign alone is all we have here.
            return (a, a < 0)
        }
        // No header — fall back to the old positional guess, minus the bug that
        // let a date column parse as a very large amount.
        guard let a = firstAmount(in: cols) else { return nil }
        return (a, a < 0)
    }

    private static func csvDescription(_ cols: [String], layout: CSVLayout?) -> String {
        if let i = layout?.desc, cols.indices.contains(i) {
            let d = cols[i].trimmingCharacters(in: .whitespaces)
            if !d.isEmpty { return d }
        }
        // Longest column that is neither a date nor an amount.
        let d = cols
            .filter { parseDate($0) == nil && parseAmount($0) == nil }
            .max(by: { $0.count < $1.count })?
            .trimmingCharacters(in: .whitespaces)
        return (d?.isEmpty == false ? d! : "Transaction")
    }

    /// Whether a file's slash dates are dd/MM or MM/dd, decided from evidence.
    static func detectDayMonthOrder(rows: [[String]], dateColumn: Int?) -> DayMonthOrder {
        let re = try? NSRegularExpression(pattern: #"^(\d{1,2})[/\-.](\d{1,2})([/\-.]\d{2,4})?$"#)
        guard let re else { return .ambiguous }
        var firstAbove12 = false, secondAbove12 = false
        for cols in rows {
            let candidates: [String] = dateColumn.map { i in
                cols.indices.contains(i) ? [cols[i]] : []
            } ?? cols
            for raw in candidates {
                let s = raw.trimmingCharacters(in: .whitespaces)
                let r = NSRange(s.startIndex..., in: s)
                guard let m = re.firstMatch(in: s, range: r),
                      let r1 = Range(m.range(at: 1), in: s),
                      let r2 = Range(m.range(at: 2), in: s),
                      let a = Int(s[r1]), let b = Int(s[r2]) else { continue }
                if a > 12 { firstAbove12 = true }
                if b > 12 { secondAbove12 = true }
            }
        }
        // Both can't be the day. If they disagree the file is inconsistent, so
        // stay ambiguous rather than committing to a wrong reading.
        if firstAbove12 && !secondAbove12 { return .dayFirst }
        if secondAbove12 && !firstAbove12 { return .monthFirst }
        return .ambiguous
    }

    /// Split a CSV line respecting double-quoted fields.
    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Rightmost money-shaped column. Used only when a file has no usable header
    /// — `csvLayout` names the columns whenever one exists, because the rightmost
    /// number is the running balance in most bank exports, not the charge.
    private static func firstAmount(in cols: [String]) -> Double? {
        for c in cols.reversed() { if let a = parseAmount(c) { return a } }
        return nil
    }
    private static func firstDate(in cols: [String], order: DayMonthOrder = .ambiguous) -> Date? {
        for c in cols { if let d = parseDate(c, order: order) { return d } }
        return nil
    }

    // MARK: PDF text

    /// Scan extracted PDF text line-by-line for "<date> <description> <amount>".
    static func parsePDFText(_ text: String) -> [ParsedLine] {
        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var result: [ParsedLine] = []
        for line in lines {
            // Need both a date and a trailing amount to consider it a row.
            guard let date = firstDateRegex(in: line),
                  let amount = trailingAmount(in: line) else { continue }
            // Description = the middle, with the date prefix and amount suffix stripped.
            var desc = line
            if let r = desc.range(of: #"^\S+\s+"#, options: .regularExpression) {
                desc.removeSubrange(r)
            }
            if let r = desc.range(of: #"[-+]?[$€£]?\s?[0-9,]+\.[0-9]{2}\s*(CR|DR)?$"#,
                                  options: .regularExpression) {
                desc.removeSubrange(r)
            }
            desc = desc.trimmingCharacters(in: .whitespaces)
            if desc.isEmpty { desc = "Transaction" }
            result.append(ParsedLine(date: date, desc: desc, amountCents: Money.centsFromDouble(amount), lowConfidence: true))
        }
        return result
    }

    private static func firstDateRegex(in line: String) -> Date? {
        let token = line.split(separator: " ").first.map(String.init) ?? line
        return parseDate(token)
    }

    /// Find a money amount at the END of a line; "CR" suffix => a credit (negative).
    private static func trailingAmount(in line: String) -> Double? {
        guard let range = line.range(
            of: #"[-+]?[$€£]?\s?[0-9,]+\.[0-9]{2}\s*(CR|DR)?$"#,
            options: .regularExpression
        ) else { return nil }
        let matched = String(line[range])
        let isCredit = matched.uppercased().contains("CR") || matched.contains("-")
        guard var value = parseAmount(matched) else { return nil }
        value = abs(value)
        return isCredit ? -value : value
    }

    // MARK: Shared scalar parsers

    /// Parse a money string like "$1,234.56", "1234.56", "-12.00", "45.00 CR".
    static func parseAmount(_ s: String) -> Double? {
        var t = s.uppercased().trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }

        // A date is not an amount. The old version stripped every character that
        // wasn't a digit or a dot and parsed whatever survived, so "16/05/2026"
        // became 16,052,026.00 and "7-ELEVEN" became -7. Both then competed to be
        // a row's amount.
        // A dot is only a date separator in the three-part form (16.05.2026);
        // treating it as one everywhere would classify the amount "12.5" as a date.
        if t.range(of: #"^\d{1,4}[/\-]\d{1,2}([/\-]\d{1,4})?$|^\d{1,2}\.\d{1,2}\.\d{2,4}$"#,
                   options: .regularExpression) != nil { return nil }

        let paren = t.hasPrefix("(") && t.hasSuffix(")")
        let isCredit = t.contains("CR")
        t = t.replacingOccurrences(of: "CR", with: "")
             .replacingOccurrences(of: "DR", with: "")
        // Strip only currency decoration. Anything else that isn't money now fails
        // the shape check below instead of being mangled into a number.
        t = t.replacingOccurrences(of: #"[\s$€£¥₹()]"#, with: "", options: .regularExpression)

        guard t.range(of: #"^[+\-]?\d{1,3}(,\d{3})+(\.\d+)?$|^[+\-]?\d+(\.\d+)?$"#,
                      options: .regularExpression) != nil else { return nil }

        let isNeg = t.hasPrefix("-")
        let digits = t.replacingOccurrences(of: ",", with: "")
                      .trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard let v = Double(digits) else { return nil }
        return (isCredit || isNeg || paren) ? -v : v
    }

    /// Which component of a slash date comes first. Decided per file from the data
    /// rather than assumed, because a fixed preference silently swaps day and month
    /// for every date where both are 12 or lower.
    enum DayMonthOrder { case dayFirst, monthFirst, ambiguous }

    /// Parse a date in several common statement formats.
    static func parseDate(_ s: String, order: DayMonthOrder = .ambiguous) -> Date? {
        let raw = s.trimmingCharacters(in: .whitespaces)
        // DateFormatter month symbols are case-sensitive, but banks print months in
        // any case — Standard Chartered/HSBC often use UPPERCASE ("16 MAY"). Try the
        // string as-is and a title-cased variant so all casings parse.
        var candidates = [raw]
        let titled = titleCasedWords(raw)
        if titled != raw { candidates.append(titled) }

        // Formats with a spelled-out month, or an ISO year first, are unambiguous
        // and must be tried before any numeric ordering guess.
        let unambiguous = [
            "yyyy-MM-dd", "dd MMM yyyy", "d MMM yyyy", "dd MMM", "MMM dd, yyyy",
            "dd MMMM yyyy", "d MMMM yyyy", "dd MMMM", "d MMMM"
        ]
        let dayFirst   = ["dd/MM/yyyy", "dd/MM/yy", "d/M/yyyy", "dd-MM-yyyy",
                          "dd.MM.yyyy", "dd/MM", "d/M"]
        let monthFirst = ["MM/dd/yyyy", "MM/dd/yy", "M/d/yyyy", "MM/dd", "M/d"]
        // `.ambiguous` keeps day-first leading, matching the previous behaviour for
        // files that give us no evidence either way.
        let formats: [String]
        switch order {
        case .monthFirst: formats = unambiguous + monthFirst + dayFirst
        case .dayFirst, .ambiguous: formats = unambiguous + dayFirst + monthFirst
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for f in formats {
            df.dateFormat = f
            for t in candidates {
                guard let d = df.date(from: t) else { continue }
                // Formats without a year default to 2000; roll forward to this year.
                if !f.contains("yy") {
                    let cal = Calendar.current
                    let now = Date()
                    var comps = cal.dateComponents([.day, .month], from: d)
                    comps.year = cal.component(.year, from: now)
                    let candidate = cal.date(from: comps) ?? d
                    // A year-less date that lands in the future belongs to last year
                    // (e.g. a December statement imported the following January).
                    if candidate > now {
                        comps.year = cal.component(.year, from: now) - 1
                        return cal.date(from: comps) ?? candidate
                    }
                    return candidate
                }
                return d
            }
        }
        return nil
    }

    /// Title-case each alphabetic word ("MAY" -> "May"), leaving numeric tokens
    /// untouched — used so case-variant month names parse.
    private static func titleCasedWords(_ s: String) -> String {
        s.split(separator: " ").map { word -> String in
            guard word.contains(where: { $0.isLetter }) else { return String(word) }
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}
