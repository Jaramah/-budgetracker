import Foundation
import PDFKit
import CoreGraphics

/// Coordinate-based PDF statement parser.
///
/// WHY coordinates (not plain text): PDFKit's `page.string` linearises a page in
/// stream order, which scrambles multi-column bank tables. Standard Chartered, for
/// example, prints all descriptions in one block and the date/amount rows in a
/// separate block — so a text-order "DATE DESC AMOUNT" scan finds nothing. And
/// Trust wraps long merchant names onto the lines above/below the amount, so a
/// line scan splits one transaction across several rows.
///
/// This parser rebuilds the visual layout: it gets every word's bounding box,
/// groups words into visual ROWS by their y-position, and splits each row into
/// date / description / amount COLUMNS by x-position. Wrapped description
/// fragments (rows with text but no date+amount) are attached to the nearest
/// transaction row within the description column band. Validated against real
/// DBS, OCBC, UOB, Trust and Standard Chartered statements.
enum CoordinateStatementParser {

    // MARK: Regex
    private static let reDateNum  = try! NSRegularExpression(pattern: #"^\d{1,2}$"#)
    private static let reMonAbbr  = try! NSRegularExpression(pattern: #"^[A-Za-z]{2,3}$"#)  // 2-3 letters (handles truncated "Ju", "Ma")
    private static let reDateSlash = try! NSRegularExpression(pattern: #"^\d{1,2}/\d{1,2}(/\d{2,4})?$"#)
    private static let reAmount   = try! NSRegularExpression(
        pattern: #"^\(?[+\-]?[\d,]+\.\d{2}(CR|DR)?\)?$"#, options: [.caseInsensitive])

    private static let noise = [
        "previous balance", "new balance", "total outstanding", "balance from previous",
        "minimum payment", "new transactions", "sub-total", "subtotal", "cashback summary",
        "activity summary", "transaction details", "description", "amount due",
        "total cashback", "eligible retail", "minimum payment due", "rewards summary"
    ]
    private static let stopZone = [
        "cashback summary", "instalment payment plan", "instalment plans summary",
        "points summary", "rewards summary"
    ]
    private static let resumeZone = ["transaction details", "post trans", "transaction posting"]

    // MARK: Word / Row models
    private struct Word { let text: String; let x0: CGFloat; let x1: CGFloat; let yMid: CGFloat }
    private struct Anchor {
        let y: CGFloat
        let date: String
        let amount: Int
        var descWords: [Word]
        let dateMaxX: CGFloat
        let amountX: CGFloat
        var extra: [(y: CGFloat, text: String)] = []
    }

    // MARK: Entry point
    static func parse(url: URL) -> [StatementParser.ParsedLine] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var out: [StatementParser.ParsedLine] = []
        var skipping = false

        print("🔍 CoordinateParser: parsing \(doc.pageCount) page(s)")

        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            let allWords = words(on: page)
            print("📄 Page \(p+1): \(allWords.count) words extracted")
            let rows = groupRows(words: allWords)
            print("📊 Page \(p+1): grouped into \(rows.count) rows")
            var anchors: [Anchor] = []
            var textRows: [(y: CGFloat, x0: CGFloat, x1: CGFloat, text: String)] = []

            for (rowIdx, row) in rows.enumerated() {
                let low = row.map { $0.text }.joined(separator: " ").lowercased()
                if resumeZone.contains(where: { low.contains($0) }) {
                    print("▶️  Row \(rowIdx): RESUME zone detected: \(low.prefix(60))")
                    skipping = false
                }
                if stopZone.contains(where: { low.contains($0) }) {
                    print("⏸️  Row \(rowIdx): STOP zone detected: \(low.prefix(60))")
                    skipping = true
                }
                if skipping { continue }

                // Try leading dates first (DBS/OCBC/Trust layout: DATE DESC AMOUNT)
                let (leadDates, consumed) = leadingDates(row)
                
                // Find the rightmost amount
                var amt: Int? = nil
                var amtIndex: Int? = nil
                if row.count > consumed {
                    var j = row.count - 1
                    while j >= consumed {
                        if let a = parseAmount(row[j].text) { amt = a; amtIndex = j; break }
                        j -= 1
                    }
                }

                // If we found an amount but no leading dates, try trailing dates
                // (Standard Chartered layout: DESC AMOUNT DATE DATE)
                var finalDates = leadDates
                var descStart = consumed
                var descEnd = amtIndex ?? row.count
                
                if finalDates.isEmpty, let ai = amtIndex, ai < row.count - 1 {
                    let (trailDates, _) = leadingDates(Array(row[(ai+1)...]))
                    if !trailDates.isEmpty {
                        finalDates = trailDates
                        descStart = consumed
                        descEnd = ai
                        print("🔄 Row \(rowIdx): found trailing dates after amount")
                    }
                }

                if let firstDate = finalDates.first, let amount = amt, let ai = amtIndex {
                    let descWords = Array(row[descStart..<descEnd])
                    let desc = descWords.map { $0.text }.joined(separator: " ")
                    print("✅ Row \(rowIdx): ANCHOR found — date=\(firstDate.text) amt=\(amount) desc=\(desc.prefix(40))")
                    anchors.append(Anchor(
                        y: row[0].yMid,
                        date: firstDate.text,
                        amount: amount,
                        descWords: descWords,
                        dateMaxX: finalDates.last!.x1,
                        amountX: row[ai].x0))
                } else if finalDates.isEmpty && amt == nil {
                    let txt = row.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    if let f = txt.first, !f.isNumber, !txt.isEmpty {
                        textRows.append((row[0].yMid,
                                         row.map { $0.x0 }.min() ?? 0,
                                         row.map { $0.x1 }.max() ?? 0,
                                         txt))
                    }
                } else {
                    // Debug: row had date or amount but not both
                    if !finalDates.isEmpty || amt != nil {
                        print("⚠️  Row \(rowIdx): partial match — dates=\(finalDates.count) amt=\(amt != nil ? "YES" : "NO") consumed=\(consumed) rowLen=\(row.count)")
                        print("    Text: \(row.map { $0.text }.joined(separator: " ").prefix(80))")
                    }
                }
            }

            if anchors.isEmpty {
                print("⚠️  Page \(p+1): NO anchors found (no rows with date+amount)")
                continue
            }

            print("📌 Page \(p+1): \(anchors.count) anchor(s) found, attaching description fragments...")
            // Description column band (per page).
            let dateX = anchors.map { $0.dateMaxX }.max() ?? 0
            let amtX  = anchors.map { $0.amountX }.min() ?? .greatestFiniteMagnitude

            for tr in textRows where tr.x0 >= dateX - 5 && tr.x1 <= amtX + 5 {
                if let idx = nearestAnchorIndex(anchors, y: tr.y), abs(anchors[idx].y - tr.y) <= 13 {
                    anchors[idx].extra.append((tr.y, tr.text))
                }
            }

            for a in anchors {
                let base = a.descWords.map { $0.text }.joined(separator: " ")
                let frags = a.extra.sorted { $0.y < $1.y }
                let above = frags.filter { $0.y < a.y }.map { $0.text }
                let below = frags.filter { $0.y >= a.y }.map { $0.text }
                var desc = cleanDesc(([above.joined(separator: " "), base, below.joined(separator: " ")])
                    .filter { !$0.isEmpty }.joined(separator: " "))
                let dlow = desc.lowercased()
                // FIXED: only drop if the description is ENTIRELY a noise phrase, not if
                // it merely contains one. A transaction "New World Supermarket" or "Digital
                // Transaction Services" shouldn't be filtered just because it contains "new"
                // or "transaction". Full-phrase match prevents false positives.
                if !desc.isEmpty, noise.contains(where: { dlow == $0 || dlow.hasPrefix($0 + " ") || dlow.hasSuffix(" " + $0) }) {
                    print("🗑️  Dropping noise row: \(desc.prefix(50))")
                    continue
                }
                if desc.isEmpty { desc = "Transaction" }
                let date = StatementParser.parseDate(a.date) ?? Date()
                print("💾 EMIT: \(a.date) | \(desc.prefix(30)) | \(a.amount)¢")
                out.append(StatementParser.ParsedLine(
                    date: date, desc: desc, amountCents: a.amount, lowConfidence: false))
            }
        }
        print("✅ CoordinateParser: DONE, returning \(out.count) transaction(s)")
        return out
    }

    // MARK: Word extraction (bounding boxes)
    /// Build words with bounding boxes from a page's characters.
    ///
    /// CRITICAL: `PDFPage.characterBounds(at:)` indexes the page string as an
    /// NSString (UTF-16 code units), NOT Swift `Character` (grapheme clusters).
    /// Iterating `Array(page.string)` and passing that index into
    /// `characterBounds(at:)` desyncs the two index spaces the moment the text
    /// contains anything that isn't a 1:1 grapheme↔UTF-16 mapping — which
    /// scrambles every word's position. We therefore iterate the NSString by
    /// UTF-16 unit so the index we split on is the exact index PDFKit measures.
    private static func words(on page: PDFPage) -> [Word] {
        guard let content = page.string, !content.isEmpty else { return [] }
        let ns = content as NSString
        let total = min(ns.length, page.numberOfCharacters)
        guard total > 0 else { return [] }

        var result: [Word] = []
        var cur = ""
        var rect: CGRect? = nil

        func flush() {
            if !cur.isEmpty, let r = rect {
                result.append(Word(text: cur, x0: r.minX, x1: r.maxX, yMid: r.midY))
            }
            cur = ""; rect = nil
        }

        for i in 0..<total {
            let unit = ns.character(at: i)                 // UTF-16 code unit
            let scalar = UnicodeScalar(unit)
            let isWhitespace = (unit == 0x20 || unit == 0x0A || unit == 0x0D ||
                                unit == 0x09 || unit == 0x0C || unit == 0xA0)
            if isWhitespace {
                flush()
                continue
            }
            let b = page.characterBounds(at: i)
            if b.isNull || b.isInfinite || b.width == 0 || b.height == 0 { continue }
            rect = (rect == nil) ? b : rect!.union(b)
            if let s = scalar { cur.unicodeScalars.append(s) }
        }
        flush()
        return result
    }

    /// Group words into visual rows by y (midpoint). The tolerance adapts to the
    /// page's glyph height so it works regardless of PDFKit's coordinate scale.
    private static func groupRows(words: [Word], yTol overrideTol: CGFloat? = nil) -> [[Word]] {
        guard !words.isEmpty else { return [] }
        let yTol = overrideTol ?? adaptiveYTolerance(words)
        let sorted = words.sorted { ($0.yMid, $0.x0) < ($1.yMid, $1.x0) }
        var rows: [[Word]] = []
        for w in sorted {
            if let idx = rows.firstIndex(where: { abs(($0.first?.yMid ?? -99999) - w.yMid) <= yTol }) {
                rows[idx].append(w)
            } else {
                rows.append([w])
            }
        }
        for i in rows.indices { rows[i].sort { $0.x0 < $1.x0 } }
        return rows.sorted { ($0.first?.yMid ?? 0) < ($1.first?.yMid ?? 0) }
    }

    /// Estimate a row-grouping tolerance from the spacing between distinct y values.
    private static func adaptiveYTolerance(_ words: [Word]) -> CGFloat {
        let ys = words.map { $0.yMid }.sorted()
        var gaps: [CGFloat] = []
        var last = ys.first ?? 0
        for y in ys.dropFirst() {
            let g = abs(y - last)
            if g > 1 { gaps.append(g) }
            last = y
        }
        guard !gaps.isEmpty else { return 3.5 }
        gaps.sort()
        let medianGap = gaps[gaps.count / 2]
        // Group within ~40% of the typical line spacing, clamped to a sane range.
        return min(max(medianGap * 0.4, 2.5), 8.0)
    }

    // MARK: Column helpers
    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Consume up to two leading date columns ("16 May" or "16/05").
    private static func leadingDates(_ row: [Word]) -> (dates: [Word], consumed: Int) {
        var dates: [Word] = []
        var i = 0
        while i < row.count {
            let t = row[i].text
            if matches(reDateSlash, t) {
                dates.append(row[i]); i += 1
            } else if i + 1 < row.count,
                      matches(reDateNum, t), matches(reMonAbbr, row[i + 1].text) {
                let merged = Word(text: t + " " + row[i + 1].text,
                                  x0: row[i].x0, x1: row[i + 1].x1, yMid: row[i].yMid)
                dates.append(merged); i += 2
            } else { break }
            if dates.count == 2 { break }
        }
        return (dates, i)
    }

    private static func parseAmount(_ token: String) -> Int? {
        let r = NSRange(token.startIndex..., in: token)
        guard matches(reAmount, token) else { return nil }
        let paren = token.hasPrefix("(") && token.hasSuffix(")")
        let up = token.uppercased()
        let credit = token.hasPrefix("+") || up.hasSuffix("CR") || paren
        
        // SKIP credits entirely — we only want debits (charges/expenses)
        guard !credit else { return nil }
        
        let num = token.replacingOccurrences(of: #"[^\d.]"#, with: "", options: .regularExpression)
        guard let val = Double(num) else { return nil }
        _ = r
        let cents = Int((val * 100).rounded())
        return cents  // Positive = debit/charge
    }

    private static func nearestAnchorIndex(_ anchors: [Anchor], y: CGFloat) -> Int? {
        guard !anchors.isEmpty else { return nil }
        var best = 0
        var bestD = CGFloat.greatestFiniteMagnitude
        for (i, a) in anchors.enumerated() {
            let d = abs(a.y - y)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    private static func cleanDesc(_ s: String) -> String {
        var out = s
        let subs: [(String, String)] = [
            (#"(?i)transaction ref\s*\w*"#, ""),
            (#"\b\d{15,}\b"#, ""),
            (#"(?i)ref no\.?\s*:?\s*"#, ""),
            (#"(?i)\b\d[\d,]*\.\d{2}\s*[A-Z]{3}\b"#, ""),               // 408.25 MYR
            (#"(?i)\b\d+\s*[A-Z]{3}\s*=\s*[\d.]+\s*[A-Z]{3}\b"#, ""),   // 1 MYR = 0.3257 SGD
            (#"(?i)\b\d[\d,]*\.\d{2}\b"#, "")                            // stray FCY numbers
        ]
        for (pat, rep) in subs {
            out = out.replacingOccurrences(of: pat, with: rep, options: .regularExpression)
        }
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespaces)
    }
}
