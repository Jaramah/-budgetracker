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

    static func parse(url: URL) throws -> [ParsedLine] {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "csv", "txt":
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = parseCSV(text)
            if lines.isEmpty { throw ParseError.nothingFound }
            return lines
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
            // Prefer the line parser on ties (it's the clean-text default); coord and
            // block only win when they strictly score higher.
            var best = lines
            if score(coord) > score(best) { best = coord }
            if score(block) > score(best) { best = block }
            if !best.isEmpty { return best }
            // Fallback: naive single-line text scan for unusual layouts.
            let fallback = parsePDFText(text)
            if fallback.isEmpty { throw ParseError.nothingFound }
            return fallback
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

    // MARK: CSV

    /// Heuristic CSV parser. Finds the column that looks like a date, the one that
    /// looks like an amount, and treats the longest remaining text column as the
    /// description. Handles quoted fields and an optional header row.
    static func parseCSV(_ text: String) -> [ParsedLine] {
        let rawRows = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rawRows.isEmpty else { return [] }

        var rows = rawRows.map { splitCSVLine($0) }

        // Drop a header row if the first row has no parseable amount.
        if let first = rows.first, firstAmount(in: first) == nil {
            rows.removeFirst()
        }

        var result: [ParsedLine] = []
        for cols in rows {
            guard let amount = firstAmount(in: cols) else { continue }
            let date = firstDate(in: cols) ?? Date()
            // Description = longest column that isn't the date or the amount text.
            let desc = cols
                .filter { parseDate($0) == nil && parseAmount($0) == nil }
                .max(by: { $0.count < $1.count })?
                .trimmingCharacters(in: .whitespaces) ?? "Transaction"
            let lowConf = firstDate(in: cols) == nil
            result.append(ParsedLine(date: date, desc: desc, amountCents: Money.centsFromDouble(amount), lowConfidence: lowConf))
        }
        return result
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

    private static func firstAmount(in cols: [String]) -> Double? {
        for c in cols.reversed() { if let a = parseAmount(c) { return a } }
        return nil
    }
    private static func firstDate(in cols: [String]) -> Date? {
        for c in cols { if let d = parseDate(c) { return d } }
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
        guard t.range(of: #"[0-9]"#, options: .regularExpression) != nil else { return nil }
        let isCredit = t.contains("CR")
        let isNeg = t.contains("-")
        t = t.replacingOccurrences(of: "CR", with: "")
             .replacingOccurrences(of: "DR", with: "")
        t = t.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
             .joined()
        guard let v = Double(t) else { return nil }
        return (isCredit || isNeg) ? -v : v
    }

    /// Parse a date in several common statement formats.
    static func parseDate(_ s: String) -> Date? {
        let raw = s.trimmingCharacters(in: .whitespaces)
        // DateFormatter month symbols are case-sensitive, but banks print months in
        // any case — Standard Chartered/HSBC often use UPPERCASE ("16 MAY"). Try the
        // string as-is and a title-cased variant so all casings parse.
        var candidates = [raw]
        let titled = titleCasedWords(raw)
        if titled != raw { candidates.append(titled) }

        let formats = [
            "dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "dd-MM-yyyy",
            "dd/MM/yy", "MM/dd/yy", "dd MMM yyyy", "dd MMM", "MMM dd, yyyy",
            "dd.MM.yyyy", "d/M/yyyy", "d MMM yyyy", "dd/MM", "d/M",
            "dd MMMM yyyy", "d MMMM yyyy", "dd MMMM", "d MMMM"   // full month names
        ]
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
