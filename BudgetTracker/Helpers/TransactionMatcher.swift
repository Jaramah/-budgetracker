import Foundation

/// Matches statement charges to logged credit transactions using
/// **exact cents + a date tolerance window + a description tiebreaker** —
/// never exact date, and never amount-alone (which silently drops genuine
/// same-amount purchases, e.g. two S$4.50 kopis days apart).
enum TransactionMatcher {

    /// User-configurable tolerance, read from AppStorage. Default ±4 days.
    static var windowDays: Int {
        let v = UserDefaults.standard.integer(forKey: "matchWindowDays")
        return v == 0 ? 4 : v
    }

    /// Exact cents equality (no float fuzz needed anymore).
    static func sameAmount(_ a: Int, _ b: Int) -> Bool { a == b }

    static func withinWindow(_ a: Date, _ b: Date, days: Int) -> Bool {
        let secs = abs(a.timeIntervalSince(b))
        return secs <= Double(days) * 86_400
    }

    /// Crude description similarity: do they share a meaningful token?
    /// Used only as a *tiebreaker* when several candidates share the amount+window,
    /// so we link the most plausible one rather than an arbitrary pick.
    static func descriptionScore(_ a: String, _ b: String) -> Int {
        let stop: Set<String> = ["the", "and", "pte", "ltd", "sg", "singapore", "pos", "card", "payment"]
        func tokens(_ s: String) -> Set<String> {
            Set(s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stop.contains($0) })
        }
        return tokens(a).intersection(tokens(b)).count
    }

    /// Find the best logged credit transaction for a statement charge:
    /// same cents, within the window; prefer higher description overlap, then
    /// closest date. Excludes already-linked ones so each logged txn links once.
    static func bestMatch(
        amountCents: Int,
        date: Date,
        desc: String,
        in candidates: [Transaction],
        excludingIDs: Set<UUID> = [],
        days: Int? = nil
    ) -> Transaction? {
        let w = days ?? windowDays
        let pool = candidates
            .filter { !excludingIDs.contains($0.id) }
            .filter { sameAmount($0.amountCents, amountCents) }
            .filter { withinWindow($0.date, date, days: w) }
        return pool.max { lhs, rhs in
            let ls = descriptionScore(lhs.note, desc)
            let rs = descriptionScore(rhs.note, desc)
            if ls != rs { return ls < rs }
            // Tie on description → closer date wins (so it sorts last in max()).
            return abs(lhs.date.timeIntervalSince(date)) > abs(rhs.date.timeIntervalSince(date))
        }
    }
}
