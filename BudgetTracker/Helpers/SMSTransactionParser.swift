import Foundation

/// Turns a bank alert SMS into a transaction the user can confirm.
///
/// **iOS apps cannot read SMS.** There is no API at any permission level, and the
/// one SMS-adjacent extension point (`ILMessageFilterExtension`) is sandboxed by
/// Apple specifically so it cannot pass anything to its containing app. So this
/// never reads the inbox — it parses text the user has handed over, by pasting it
/// or sharing it from Messages.
///
/// Nothing is saved without confirmation: a parse only pre-fills the Add
/// Transaction screen. That matters here, because SMS is an untrusted channel and
/// a convincing fake alert should never be able to write to someone's ledger on
/// its own.
enum SMSTransactionParser {

    struct Result {
        let amountCents: Int
        /// Money received rather than sent.
        let isIncoming: Bool
        /// Merchant or person, when the alert names one.
        let counterparty: String?
        /// The date the alert stated, if any. `nil` means "use today".
        let date: Date?
        /// Description to pre-fill, matching the wording statement imports use so
        /// the two sources agree for matching and subscription detection.
        let suggestedNote: String
    }

    // MARK: Vocabulary

    /// At least one of these must appear, so an ordinary text message or a
    /// one-time-passcode never parses into a transaction.
    private static let markers = [
        "paynow", "pay now", "fast", "transfer", "debited", "credited",
        "charged", "paid to", "payment of"
    ]
    private static let incomingWords = ["received", "credited", "credit of", "refund"]
    private static let outgoingWords = [
        "paid", "debited", "transferred", "transfer of", "sent", "charged", "spent",
        "made a paynow", "payment of"
    ]

    /// Words that are never part of a payee name.
    private static let namePattern = #"(?i)\b(?:paynow|pay now|via|your|our|the|account|acct|ending|a/c|card|ref(?:erence)?|no|transaction)\b"#

    // MARK: Entry point

    static func parse(_ text: String) -> Result? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let low = trimmed.lowercased()

        guard markers.contains(where: { low.contains($0) }) else { return nil }
        guard let cents = amountCents(in: trimmed), cents > 0 else { return nil }

        let incoming = incomingWords.contains { low.contains($0) }
        let outgoing = outgoingWords.contains { low.contains($0) }
        // Both present, or neither, is read as outgoing: an alert that says
        // "debited … to X" is a payment even though it also says "from your
        // account", and money leaving is the far more common alert.
        let isIncoming = incoming && !outgoing

        let party = counterparty(in: trimmed, isIncoming: isIncoming)
        let isPayNow = low.contains("paynow") || low.contains("pay now")

        let note: String
        if let party {
            // Card alerts name a merchant, so the merchant alone is the better
            // note; PayNow keeps the directional wording statements use.
            note = isPayNow ? (isIncoming ? "PayNow from \(party)" : "PayNow to \(party)") : party
        } else {
            note = isIncoming ? "PayNow received" : (isPayNow ? "PayNow transfer" : "Card payment")
        }

        return Result(amountCents: cents,
                      isIncoming: isIncoming,
                      counterparty: party,
                      date: StatementParser.firstDate(inText: trimmed),
                      suggestedNote: note)
    }

    // MARK: Pieces

    /// First money amount in the message. Handles "SGD25.00", "S$ 1,200.00",
    /// "$8", and the trailing "18.50 SGD" form.
    static func amountCents(in text: String) -> Int? {
        let pattern = #"(?:SGD|S\$|\$)\s*([\d,]+(?:\.\d{1,2})?)|\b([\d,]+\.\d{2})\s*SGD\b"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        for group in 1...2 {
            guard let r = Range(m.range(at: group), in: text) else { continue }
            let raw = String(text[r]).replacingOccurrences(of: ",", with: "")
            if let v = Double(raw) { return Int((v * 100).rounded()) }
        }
        return nil
    }

    /// The other party. Direction decides which preposition names them: a debit
    /// alert reads "debited from your account … to MERCHANT", so keying on "from"
    /// would return the user's own account rather than the payee.
    static func counterparty(in text: String, isIncoming: Bool) -> String? {
        let prepositions = isIncoming ? ["from"] : ["to", "at"]
        var best: String?
        for p in prepositions {
            let pattern = #"(?i)\b\#(p)\s+(.+)$"#
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range(at: 1), in: text) else { continue }
                guard let name = cleanName(String(text[r])) else { continue }
                // Prefer the tightest candidate: a later preposition is nearer the
                // name, so its tail carries less of the sentence with it.
                if best == nil || name.count < best!.count { best = name }
            }
        }
        return best
    }

    /// Trim a trailing clause off a candidate name and strip boilerplate.
    private static func cleanName(_ raw: String) -> String? {
        var s = raw
        // Cut at the clause that follows the name ("on 25 Aug", "Ref 123", ". ").
        if let r = s.range(of: #"(?i)\s+\bon\b\s|\.\s|\bref\b|\son\s\d"#, options: .regularExpression) {
            s = String(s[s.startIndex..<r.lowerBound])
        }
        s = s.replacingOccurrences(of: namePattern, with: " ", options: .regularExpression)
        // Long digit runs are account or reference numbers, never a name. Short
        // ones are kept so "7-ELEVEN" survives.
        s = s.replacingOccurrences(of: #"\b\d{3,}\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,-:;"))
        guard s.range(of: #"\p{L}{2,}"#, options: .regularExpression) != nil else { return nil }
        return s.count > 40 ? String(s.prefix(40)).trimmingCharacters(in: .whitespaces) : s
    }
}
