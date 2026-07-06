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
    private static let monAbbr = try! NSRegularExpression(pattern: #"^[A-Za-z]{2,9}$"#)  // candidate month; validated by parseDate before use
    private static let dateSlash = try! NSRegularExpression(pattern: #"^\d{1,2}/\d{1,2}(/\d{2,4})?$"#)
    private static let cardNo = try! NSRegularExpression(pattern: #"\d{4}[- ]\d{4}[- ]\d{4}[- ]\d{4}"#)  // card-number header line

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
        let pages = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }
        return parse(pageTexts: pages)
    }

    /// Alternative parse for the "trailing amount block" layout (UOB): every
    /// transaction is printed as `POST TRANS  DESCRIPTION` with **no** inline amount,
    /// and all the amounts follow afterwards in one contiguous column block, matched
    /// to the transactions positionally. Returns `[]` unless that layout is detected,
    /// so it only competes for UOB-style statements and can't regress the others.
    static func parseBlock(url: URL) -> [StatementParser.ParsedLine] {
        guard let doc = PDFDocument(url: url) else { return [] }
        let pages = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }
        return parseBlock(pageTexts: pages)
    }

    static func parseBlock(pageTexts: [String]) -> [StatementParser.ParsedLine] {
        let physical = pageTexts.flatMap {
            $0.split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }.filter { !$0.isEmpty }

        // Only handle this layout when amounts really are batched: require a run of
        // ≥3 consecutive lines that are nothing but a monetary amount.
        var run = 0, maxRun = 0
        for l in physical {
            if l.split(separator: " ").count == 1, parseAmount(l) != nil { run += 1; maxRun = max(maxRun, run) }
            else { run = 0 }
        }
        guard maxRun >= 3 else { return [] }

        var out: [StatementParser.ParsedLine] = []
        var awaiting: [(date: Date, desc: String, low: Bool)] = []  // debits pending an amount
        var amounts: [Int] = []                                     // block amounts (debits), in order
        var inlineEntries = 0, noInlineEntries = 0

        func flush() {
            for (i, t) in awaiting.enumerated() where i < amounts.count {
                out.append(StatementParser.ParsedLine(
                    date: t.date, desc: t.desc, amountCents: amounts[i], lowConfidence: t.low))
            }
            awaiting.removeAll(); amounts.removeAll()
        }

        for line in physical {
            let low = line.lowercased()
            if low.contains("sub total") || low.contains("sub-total")
                || low.contains("total balance") || low.contains("end of transaction") {
                flush(); continue
            }
            if low.hasPrefix("ref no") { continue }

            // A bare amount line contributes to the block (skip credit amounts).
            let toks = line.split(separator: " ").map(String.init)
            if toks.count == 1, let (c, credit) = parseAmount(toks[0]) {
                if !credit { amounts.append(c) }
                continue
            }

            let entries = splitEntries(toks)
            if entries.isEmpty {
                // Description continuation (e.g. "SINGAPORE SG") → append to last pending.
                if !hasLeadingDate(line), !awaiting.isEmpty,
                   line.count > 2, line.first.map({ Int(String($0)) == nil }) == true {
                    awaiting[awaiting.count - 1].desc = merge(awaiting[awaiting.count - 1].desc, line)
                }
                continue
            }
            for e in entries {
                guard let d = cleanedDescription(e.descTokens.joined(separator: " ")) else { continue }
                if let (c, credit) = e.inlineAmount {
                    inlineEntries += 1
                    if !credit { out.append(StatementParser.ParsedLine(
                        date: e.date, desc: d, amountCents: c, lowConfidence: e.low)) }
                } else {
                    noInlineEntries += 1
                    awaiting.append((e.date, d, e.low))
                }
            }
        }
        flush()  // in case the section wasn't terminated by a SUB TOTAL line
        // Guard: this is the *pure* trailing-block layout only when almost every
        // transaction defers its amount to the block. A statement where many rows
        // carry an inline amount (Trust's hybrid layout) is not this shape — bail so
        // the normal line parser handles it instead.
        guard noInlineEntries >= 3, inlineEntries <= noInlineEntries / 3 else { return [] }
        return out.compactMap { line in
            guard let clean = cleanedDescription(line.desc) else { return nil }
            var l = line; l.desc = clean; return l
        }
    }

    /// One transaction parsed out of a physical line (a UOB line can carry several).
    private struct Entry { let date: Date; let low: Bool; let descTokens: [String]; let inlineAmount: (Int, Bool)? }

    /// Split a physical line into entries. Each entry starts with a `POST TRANS`
    /// date pair ("29 MAY 29 MAY"); requiring *two* consecutive day-month dates
    /// avoids splitting on a date that's really part of a description.
    private static func splitEntries(_ tokens: [String]) -> [Entry] {
        func isDayMon(_ i: Int) -> Bool {
            i + 1 < tokens.count && matches(dayNum, tokens[i]) && matches(monAbbr, tokens[i + 1])
                && StatementParser.parseDate(tokens[i] + " " + tokens[i + 1]) != nil
        }
        var starts: [Int] = []
        var i = 0
        while i + 3 < tokens.count {
            if isDayMon(i) && isDayMon(i + 2) { starts.append(i); i += 4 } else { i += 1 }
        }
        guard !starts.isEmpty else { return [] }

        var entries: [Entry] = []
        for (k, s) in starts.enumerated() {
            let end = (k + 1 < starts.count) ? starts[k + 1] : tokens.count
            // Use the transaction (2nd) date; fall back to the post date.
            let parsed = StatementParser.parseDate(tokens[s + 2] + " " + tokens[s + 3])
                ?? StatementParser.parseDate(tokens[s] + " " + tokens[s + 1])
            var desc = Array(tokens[(s + 4)..<end])
            // Pull any trailing inline amount (with optional CR/DR) off the description.
            var credit = false
            if let last = desc.last?.uppercased(), last == "CR" || last == "DR" {
                credit = (last == "CR"); desc.removeLast()
            }
            var inline: (Int, Bool)? = nil
            if let last = desc.last, let (c, cr) = parseAmount(last) {
                inline = (c, cr || credit); desc.removeLast()
            }
            entries.append(Entry(date: parsed ?? Date(), low: parsed == nil,
                                 descTokens: desc, inlineAmount: inline))
        }
        return entries
    }

    /// Testable core: parse already-extracted page strings (one per page). Keeps the
    /// PDF I/O out of the way so bank layouts can be unit-tested from plain text.
    static func parse(pageTexts: [String]) -> [StatementParser.ParsedLine] {
        var out: [StatementParser.ParsedLine] = []
        var skipping = false
        // A transaction whose date/description we've seen but whose amount is still
        // to come on a later line (Standard Chartered's split layout). A single slot
        // (not a queue) is deliberate: a fresh dated line discards a still-unpaired
        // pending, which filters spurious header rows that briefly look like a
        // transaction awaiting its amount.
        var pending: StatementParser.ParsedLine? = nil

        for text in pageTexts {
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                let low = line.lowercased()

                if resumeZone.contains(where: { low.contains($0) }) { skipping = false; continue }
                if stopZone.contains(where: { low.contains($0) }) { skipping = true }
                if skipping || line.isEmpty { continue }

                switch classify(line) {
                case .transaction(let parsed):
                    pending = nil   // a same-line transaction supersedes any dangling pending
                    out.append(parsed)
                case .dateNoAmount(let date, let desc, let lowConf):
                    // Start a transaction; its amount appears on a following line.
                    pending = StatementParser.ParsedLine(
                        date: date, desc: desc, amountCents: 0, lowConfidence: lowConf)
                case .amountOnly(let cents, let isCredit):
                    if var p = pending {
                        pending = nil
                        // Only keep debits; a credit/payment amount discards the txn.
                        if !isCredit {
                            p.amountCents = cents
                            out.append(p)
                        }
                    }
                    // No pending → a stray amount (e.g. a balance) — ignore.
                case .orphan(let text):
                    // A wrapped description fragment: attach to the pending txn if one
                    // is open, else to the row above. A bare "Transaction" placeholder
                    // (from a "DATE AMOUNT"-only line, e.g. OCBC) is replaced, not
                    // appended, so the real description isn't prefixed with it. An orphan
                    // before any transaction (page/section headers) has nothing to attach
                    // to and is simply dropped.
                    if pending != nil {
                        pending!.desc = merge(pending!.desc, text)
                    } else if let last = out.indices.last {
                        out[last].desc = merge(out[last].desc, text)
                    }
                case .ignore:
                    break
                }
            }
        }
        // Final pass: descriptions can accrete footer/header text via orphan
        // continuation lines (which bypass per-line cleaning). Re-clean each, and
        // drop any row that turns out to be a summary/total block.
        return out.compactMap { line in
            guard let clean = cleanedDescription(line.desc) else { return nil }
            var l = line; l.desc = clean; return l
        }
    }

    private enum LineKind {
        case transaction(StatementParser.ParsedLine)
        /// A dated line with no inline amount — Standard Chartered prints the amount
        /// on a following line. Held as "pending" until its amount arrives.
        case dateNoAmount(date: Date, desc: String, lowConfidence: Bool)
        /// A line that is nothing but a monetary amount (completes a pending txn).
        case amountOnly(cents: Int, isCredit: Bool)
        case orphan(String)
        case ignore
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// True if the line begins with a parseable date column (slash form or
    /// "day month"). Used so summary/header keywords only suppress *undated*
    /// lines — a genuine dated transaction whose merchant merely contains a word
    /// like "Total" (e.g. "Total Wine") must never be dropped.
    private static func hasLeadingDate(_ line: String) -> Bool {
        let toks = line.split(separator: " ").map(String.init)
        guard let f = toks.first else { return false }
        if matches(dateSlash, f) { return true }
        if toks.count >= 2, matches(dayNum, f), matches(monAbbr, toks[1]),
           StatementParser.parseDate(f + " " + toks[1]) != nil { return true }
        return false
    }

    private static func classify(_ line: String) -> LineKind {
        let low = line.lowercased()
        // Only treat summary/header keywords as noise on *undated* lines; a real
        // dated transaction (e.g. "16 May Total Wine 45.00") must pass through.
        if !hasLeadingDate(line), noise.contains(where: { low.contains($0) }) { return .ignore }

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
                      matches(dayNum, t), matches(monAbbr, tokens[consumed + 1]),
                      StatementParser.parseDate(t + " " + tokens[consumed + 1]) != nil {
                dateStrings.append(t + " " + tokens[consumed + 1]); consumed += 2
            } else { break }
            if dateStrings.count == 2 { break }
        }

        guard let firstDate = dateStrings.first else {
            // A line that is nothing but an amount (Standard Chartered prints the
            // amount on its own line, under the date/description) → complete a pending.
            if tokens.count == 1, let (c, credit) = parseAmount(tokens[0]) {
                return .amountOnly(cents: c, isCredit: credit || trailingCredit)
            }
            // No date → possibly a wrapped description fragment (orphan).
            // Only treat as orphan if it's text (not a number-y noise line).
            let firstChar = line.first.map { String($0) } ?? ""
            // A dangling ")" with no matching "(" is the tail of a split-across-lines
            // parenthesised *credit* description (OCBC: "PAYMENT BY INTERNET )" /
            // "ANNUAL FEE REVERSAL )"). Discard it so it can't leak onto the next debit.
            let danglingCredit = line.contains(")") && !line.contains("(")
            // A lone total/summary word must never become a description fragment.
            let loneSummary = ["total", "subtotal", "sub total", "sub-total"].contains(low)
            // A card-number header line ("JEREMY … 5240-4030-0103-2544") is boilerplate,
            // not a merchant — never let it seed a description.
            if line.count > 2, Int(firstChar) == nil, !danglingCredit, !loneSummary,
               !matches(cardNo, line),
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
        guard let value = cents, let ai = amtIndex, ai >= consumed else {
            // Dated line with no inline amount → Standard Chartered layout; the amount
            // is on a later line. Emit the date+description as a pending transaction.
            guard let d = cleanedDescription(tokens[consumed...].joined(separator: " ")) else { return .ignore }
            let parsed = StatementParser.parseDate(firstDate)
            return .dateNoAmount(date: parsed ?? Date(), desc: d, lowConfidence: parsed == nil)
        }
        if trailingCredit { isCredit = true }
        
        // SKIP credits entirely — we only want debits (charges/expenses)
        guard !isCredit else { return .ignore }

        guard let desc = cleanedDescription(tokens[consumed..<ai].joined(separator: " ")) else { return .ignore }

        // Flag rather than silently defaulting to today's date if it won't parse.
        let parsedDate = StatementParser.parseDate(firstDate)
        let date = parsedDate ?? Date()
        return .transaction(StatementParser.ParsedLine(
            date: date, desc: desc, amountCents: value, lowConfidence: parsedDate == nil))  // Always positive (debit)
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
        // A leading "(" marks a credit even when the closing ")" is on the next line
        // (OCBC splits parenthesised credits across two lines).
        let paren = token.hasPrefix("(")
        let credit = (sign == "+") || (suffix == "CR") || paren
        return (Int((val * 100).rounded()), credit)
    }

    private static func stripRefs(_ s: String) -> String {
        let patterns = [#"(?i)Transaction Ref\s*\w*"#, #"(?i)Ref No\.?\s*:?\s*\w*"#, #"(?i)REF NO:?\s*\w*"#]
        var out = s
        for p in patterns { out = out.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        return out
    }

    /// Multi-word summary phrases that never appear in a real merchant name, so we
    /// can drop a row containing one anywhere (unlike the generic `noise` words).
    private static let summaryPhrases = [
        "previous balance", "outstanding balance", "total outstanding", "new balance",
        "balance from previous", "minimum payment", "minimum amount", "amount due",
        "amount to pay", "total balance", "grand total", "sub total", "sub-total",
        "subtotal", "last month", "approved credit", "credit limit", "total spend"
    ]

    /// Bank legal-footer / boilerplate markers. Descriptions are truncated here to
    /// strip page-footer text that PDFKit appends to the last transaction line.
    private static let footerMarkers = [
        "trust bank singapore", "united overseas bank", "oversea-chinese",
        "standard chartered bank", "dbs bank ltd", "gst reg", "co. reg", "co.reg",
        "reg. no", "reg no", "claim against", "please note", "co. registration"
    ]

    /// Clean a raw description: strip ref numbers, cut at any embedded date (some
    /// banks concatenate several transactions onto one text line, e.g. Trust:
    /// "Grab 23 May 25 May Grab …"), and reject summary/total rows. Returns nil if
    /// the row should be ignored entirely.
    private static func cleanedDescription(_ raw: String) -> String? {
        var d = stripRefs(raw).trimmingCharacters(in: .whitespaces)
        if isSummary(d) { return nil }
        d = trimAtEmbeddedDate(d)
        d = trimAtFooter(d)
        d = stripInstalmentJunk(d).trimmingCharacters(in: .whitespaces)
        return d.isEmpty ? "Transaction" : d
    }

    /// Merge an appended fragment, replacing a bare "Transaction" placeholder.
    private static func merge(_ base: String, _ fragment: String) -> String {
        base == "Transaction" ? fragment : base + " " + fragment
    }

    /// Strip instalment noise banks tack onto a description: the original amount
    /// ("$331.11") and the counter ("004/012") — e.g. OCBC's GE CASHFLO rows.
    private static func stripInstalmentJunk(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: #"\$[\d,]+\.\d{2}"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\b\d{3}/\d{3}\b"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return out
    }

    /// Cut a description at the first bank-footer marker (case-insensitive).
    private static func trimAtFooter(_ desc: String) -> String {
        let low = desc.lowercased()
        var cut = desc.endIndex
        for marker in footerMarkers {
            if let r = low.range(of: marker) {
                let idx = desc.index(desc.startIndex, offsetBy: low.distance(from: low.startIndex, to: r.lowerBound))
                if idx < cut { cut = idx }
            }
        }
        return String(desc[desc.startIndex..<cut])
    }

    private static func isSummary(_ desc: String) -> Bool {
        let d = desc.lowercased()
        return summaryPhrases.contains { d.contains($0) }
    }

    /// Keep only the description up to (but not including) the first embedded date
    /// token — the first word is always kept so a merchant that merely starts with a
    /// month word ("May Flower") survives.
    private static func trimAtEmbeddedDate(_ desc: String) -> String {
        let toks = desc.split(separator: " ").map(String.init)
        var kept: [String] = []
        var i = 0
        while i < toks.count {
            if !kept.isEmpty {
                if matches(dateSlash, toks[i]) { break }
                if i + 1 < toks.count, matches(dayNum, toks[i]), matches(monAbbr, toks[i + 1]),
                   StatementParser.parseDate(toks[i] + " " + toks[i + 1]) != nil { break }
            }
            kept.append(toks[i]); i += 1
        }
        return kept.joined(separator: " ")
    }
}
