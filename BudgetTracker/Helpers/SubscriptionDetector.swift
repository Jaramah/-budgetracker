import Foundation
import SwiftData

/// Finds likely subscriptions in the user's transactions and upserts them as
/// `.suggested` for one-tap confirmation.
///
/// Two signals:
/// 1. **Known brand** — a merchant in `knownBrands` (Netflix, Spotify, telco…) is
///    flagged even from a single charge.
/// 2. **Recurring pattern** — an unrecognised merchant charged ≥3 times at a
///    regular interval, on a steady day of month or for a steady amount.
///
/// The pattern branch is deliberately hard to satisfy, because a habit and a
/// subscription look identical in the data: the same commute on the same date each
/// month at the same fare produces exactly the signal a monthly subscription does.
/// Four things keep those out, in order of how much work they do:
///
/// - **Once per cycle.** A subscription renews once a period. Any merchant charged
///   twice in one period is something you use, not something that renews. This
///   needs no lists and catches most everyday spending on its own.
/// - **Merchant and category exclusions.** Transport, food, groceries and health
///   are never suggested from a pattern, however even the spacing.
/// - **Three occurrences, not two.** Two charges a month apart is a coincidence.
/// - **Suggested, never active.** A pattern match is a guess, so it always needs a
///   tap. Detection only ever inserts `Subscription` rows — it never modifies a
///   transaction or a statement line, so a wrong guess cannot corrupt an import.
enum SubscriptionDetector {

    // MARK: Public API

    /// Scan `transactions`, inserting a `.suggested` Subscription for any newly
    /// detected merchant not already tracked or dismissed. Returns the number added.
    @discardableResult
    static func refresh(transactions: [Transaction], context: ModelContext) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        var knownKeys = Set(existing.map(\.matchKey))

        // Group expense transactions by normalised merchant key.
        var groups: [String: [Transaction]] = [:]
        for tx in transactions where tx.isExpense {
            guard let key = matchKey(for: tx.note) else { continue }
            groups[key, default: []].append(tx)
        }

        var byKey: [String: Subscription] = [:]
        for sub in existing where byKey[sub.matchKey] == nil { byKey[sub.matchKey] = sub }

        var added = 0
        var changed = false
        for (key, txs) in groups {
            // Already tracked: refresh it rather than skipping. The old code did
            // nothing here, so a subscription's amount and anchor were frozen at
            // whatever the first detection saw — price rises stayed invisible and
            // renewal dates drifted stale.
            if let sub = byKey[key] {
                if let latest = txs.max(by: { $0.date < $1.date }), latest.date > sub.anchorDate {
                    if sub.amountCents != abs(latest.amountCents) || sub.anchorDate != latest.date {
                        sub.amountCents = abs(latest.amountCents)
                        sub.anchorDate = latest.date
                        sub.updatedAt = .now
                        changed = true
                    }
                }
                continue
            }
            guard !knownKeys.contains(key) else { continue }
            guard let candidate = evaluate(key: key, txs: txs) else { continue }
            context.insert(candidate)
            knownKeys.insert(key)
            added += 1
        }
        if added > 0 || changed { try? context.save() }
        return added
    }

    /// Normalised, stable merchant token — the first meaningful word, lowercased.
    /// e.g. "SPOTIFY P42A314ACB STOCKHOLM SE" → "spotify", "NETFLIX.COM" → "netflix".
    ///
    /// Payment processors are stripped first. A charge routed through PayPal reads
    /// "PAYPAL *SPOTIFY", and taking the leading token would key it as "paypal" —
    /// collapsing every processor-routed subscription into one bogus group and
    /// matching none of them to their real brand.
    static func matchKey(for note: String) -> String? {
        let cleaned = strippingProcessorPrefix(note)
        let tokens = cleaned.lowercased().split { !$0.isLetter }.map(String.init)
        for t in tokens where t.count >= 2 && !noiseTokens.contains(t) {
            return t
        }
        return nil
    }

    /// Drop a leading "PAYPAL *", "SQ *", "GOOGLE *" style processor prefix.
    ///
    /// Only fires when a known processor is followed by the `*` these gateways use,
    /// so an ordinary merchant whose name starts with one of these words is left
    /// alone. Returns the original string when nothing matches.
    static func strippingProcessorPrefix(_ note: String) -> String {
        let lower = note.lowercased()
        for p in processorPrefixes {
            // "paypal *spotify", "paypal*spotify", "sq * merchant"
            guard let r = lower.range(of: #"^\#(p)\s*\*+\s*"#, options: .regularExpression) else { continue }
            let remainder = String(note[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            return remainder.isEmpty ? note : remainder
        }
        return note
    }

    /// Gateways that prefix the real merchant name. `google` and `amzn` are here
    /// because "GOOGLE *YouTube Premium" is a YouTube charge, not a Google one.
    private static let processorPrefixes = [
        "paypal", "pp", "sq", "sqc", "stripe", "tst", "toast", "google", "goog",
        "amzn", "amazon", "shopify", "gumroad", "fs", "fastspring", "chargebee",
        "paddle", "2co", "recurly", "braintree", "adyen", "wise", "revolut"
    ]

    // MARK: Heuristics

    private static func evaluate(key: String, txs: [Transaction]) -> Subscription? {
        let sorted = txs.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }

        let cadence = inferCycle(sorted)

        // Trusted, unambiguous subscription brand — flag even from one charge.
        if let brand = knownBrands[key], !ambiguousBrands.contains(key) {
            return make(name: brand, key: key, latest: latest, cycle: cadence ?? .monthly)
        }

        // Everything below is pattern-based, i.e. a guess about a merchant we don't
        // recognise. A recurring shape alone is NOT enough: a monthly commute, gym
        // run or standing grocery order all look identical to a subscription in the
        // data. Rule those out on merchant identity before trusting the pattern.
        guard !isNeverSubscription(key: key, txs: sorted) else { return nil }

        // A subscription bills once per cycle. A merchant charged more than once in
        // any single period is something you *use* repeatedly, not something that
        // renews — this alone disqualifies transport, food and groceries even when
        // their category is missing.
        guard let cadence, chargedAtMostOncePerCycle(sorted, cycle: cadence) else { return nil }

        // Three occurrences, not two. Two charges a month apart is a coincidence
        // that any regular habit produces; three at a steady interval on a steady
        // day of month is a pattern.
        guard sorted.count >= 3 else { return nil }

        // Two supporting signals, either of which is convincing on its own:
        // a stable amount, or a stable day of month. Requiring a stable amount
        // outright used to drop any subscription whose price had changed — which is
        // precisely the case worth surfacing.
        guard amountsStable(sorted) || billedOnAStableDayOfMonth(sorted) else { return nil }

        return make(name: knownBrands[key] ?? key.capitalized, key: key, latest: latest, cycle: cadence)
    }

    // MARK: False-positive guards

    /// Merchants that are never subscriptions however regular the pattern looks.
    ///
    /// Checked two ways, because either can be missing: the category the user (or
    /// the auto-categoriser) assigned, and the merchant token itself.
    static func isNeverSubscription(key: String, txs: [Transaction]) -> Bool {
        if nonSubscriptionMerchants.contains(key) { return true }
        // A single categorised charge is enough — categories are per-merchant in
        // practice, and being wrong here only costs a suggestion we didn't make.
        for tx in txs {
            guard let name = tx.category?.name.lowercased(), !name.isEmpty else { continue }
            if nonSubscriptionCategoryHints.contains(where: { name.contains($0) }) { return true }
        }
        return false
    }

    /// Whether the merchant was charged at most once in each cycle period.
    ///
    /// This is the guard that keeps everyday merchants out. Two Grab rides in one
    /// month — even on the same day, as real statements show — mean Grab cannot be
    /// a monthly subscription, no matter how even the spacing looks overall.
    static func chargedAtMostOncePerCycle(_ sorted: [Transaction], cycle: Subscription.Cycle) -> Bool {
        let cal = DateHelpers.calendar
        var seen = Set<String>()
        for tx in sorted {
            let c = cal.dateComponents([.year, .month, .weekOfYear, .day], from: tx.date)
            let bucket: String
            switch cycle {
            case .weekly:
                bucket = "\(c.year ?? 0)-w\(c.weekOfYear ?? 0)"
            case .monthly:
                bucket = "\(c.year ?? 0)-\(c.month ?? 0)"
            case .quarterly:
                bucket = "\(c.year ?? 0)-q\(((c.month ?? 1) - 1) / 3)"
            case .halfYearly:
                bucket = "\(c.year ?? 0)-h\(((c.month ?? 1) - 1) / 6)"
            case .yearly:
                bucket = "\(c.year ?? 0)"
            }
            if !seen.insert(bucket).inserted { return false }
        }
        return true
    }

    /// Whether the charges land on roughly the same day of month each period.
    /// Tolerates a couple of days for weekends and processing delays.
    static func billedOnAStableDayOfMonth(_ sorted: [Transaction]) -> Bool {
        let cal = DateHelpers.calendar
        let days = sorted.compactMap { cal.dateComponents([.day], from: $0.date).day }
        guard days.count >= 2, let lo = days.min(), let hi = days.max() else { return false }
        // Month-end billing wraps (31st, then the 1st), so also accept a tight
        // cluster measured around the end of the month.
        let direct = hi - lo
        let wrapped = (lo + 31) - hi
        return min(direct, wrapped) <= 3
    }

    /// Categories whose merchants are essentially never subscriptions. Matched as a
    /// substring so "Food & Dining" and "Transport" both hit.
    private static let nonSubscriptionCategoryHints: Set<String> = [
        "transport", "grocer", "food", "dining", "health", "medical", "housing", "petrol"
    ]

    /// Merchant keys that rule out a subscription even with no category assigned.
    /// Mirrors the auto-categoriser's transport/groceries/food/health merchants —
    /// these are the everyday merchants a regular routine makes look periodic.
    private static let nonSubscriptionMerchants: Set<String> = [
        "grab", "gojek", "comfort", "taxi", "mrt", "smrt", "bus", "transit", "ezlink",
        "shell", "esso", "caltex", "spc", "petrol", "parking",
        "fairprice", "ntuc", "cold", "giant", "sheng", "shengsiong", "redmart",
        "grocer", "market", "supermarket", "donki", "dondon",
        "mcdonald", "kfc", "burger", "starbucks", "coffee", "kopitiam", "restaurant",
        "cafe", "eatery", "subway", "pizza", "deliveroo", "foodpanda", "chatime",
        "clinic", "hospital", "pharmacy", "guardian", "watson", "dental", "polyclinic"
    ]

    private static func make(name: String, key: String, latest: Transaction, cycle: Subscription.Cycle) -> Subscription {
        Subscription(
            name: name,
            matchKey: key,
            amountCents: latest.amountCents,
            cycle: cycle,
            anchorDate: latest.date,
            cardID: latest.cardID,
            category: latest.category,
            status: .suggested
        )
    }

    /// Infer a billing cycle from the median gap between consecutive charges.
    private static func inferCycle(_ sorted: [Transaction]) -> Subscription.Cycle? {
        guard sorted.count >= 2 else { return nil }
        let cal = DateHelpers.calendar
        var gaps: [Int] = []
        for i in 1..<sorted.count {
            let days = cal.dateComponents([.day], from: sorted[i - 1].date, to: sorted[i].date).day ?? 0
            if days > 0 { gaps.append(days) }
        }
        guard !gaps.isEmpty else { return nil }
        let median = gaps.sorted()[gaps.count / 2]
        switch median {
        case 5...10:    return .weekly
        case 24...38:   return .monthly
        case 80...100:  return .quarterly
        case 170...200: return .halfYearly
        case 330...400: return .yearly
        default:        return nil
        }
    }

    /// Subscription amounts are near-constant; allow small FX/tax drift.
    private static func amountsStable(_ txs: [Transaction]) -> Bool {
        let amounts = txs.map(\.amountCents)
        guard let lo = amounts.min(), let hi = amounts.max() else { return false }
        let median = amounts.sorted()[amounts.count / 2]
        let tolerance = max(200, median / 6)   // ≥ $2 or ~15%
        return hi - lo <= tolerance
    }

    // MARK: Data

    /// Brands that are also common one-off retailers — only treat as a subscription
    /// when a recurring pattern confirms it (avoids flagging an Apple Store or Amazon
    /// purchase as a subscription).
    private static let ambiguousBrands: Set<String> = [
        "apple", "google", "amazon", "microsoft", "office"
    ]

    /// Tokens that are never a brand name — dropped when picking the match key.
    private static let noiseTokens: Set<String> = [
        "the", "by", "and", "for", "pte", "ltd", "llc", "inc", "co", "corp",
        "com", "net", "org", "www", "http", "https",
        "sg", "sgp", "se", "us", "usa", "uk", "ca", "au", "my", "hk",
        "pay", "payment", "bill", "billing", "recurring", "subscription", "sub",
        "singapore", "stockholm", "limited", "purchase", "pos", "visa", "card"
    ]

    /// Curated subscription brands → display name. Matched on the first meaningful
    /// merchant token, so single charges still surface these.
    static let knownBrands: [String: String] = [
        // Streaming video
        "netflix": "Netflix", "disney": "Disney+", "hbo": "HBO", "hulu": "Hulu",
        "youtube": "YouTube", "paramount": "Paramount+", "peacock": "Peacock",
        "crunchyroll": "Crunchyroll", "viu": "Viu", "iqiyi": "iQIYI", "hotstar": "Hotstar",
        "mubi": "MUBI", "twitch": "Twitch",
        // Music / audio
        "spotify": "Spotify", "deezer": "Deezer", "tidal": "TIDAL", "audible": "Audible",
        "soundcloud": "SoundCloud",
        // Apple / cloud / productivity
        "icloud": "iCloud+", "apple": "Apple", "dropbox": "Dropbox", "google": "Google",
        "microsoft": "Microsoft 365", "office": "Microsoft 365", "notion": "Notion",
        "evernote": "Evernote", "canva": "Canva", "adobe": "Adobe", "grammarly": "Grammarly",
        "github": "GitHub", "figma": "Figma", "slack": "Slack", "zoom": "Zoom",
        "lastpass": "LastPass", "1password": "1Password",
        // AI
        "openai": "ChatGPT", "chatgpt": "ChatGPT", "anthropic": "Claude", "claude": "Claude",
        "perplexity": "Perplexity", "midjourney": "Midjourney",
        // VPN / security
        "nordvpn": "NordVPN", "expressvpn": "ExpressVPN", "surfshark": "Surfshark",
        // News / reading / misc
        "medium": "Medium", "patreon": "Patreon", "substack": "Substack",
        "linkedin": "LinkedIn", "duolingo": "Duolingo", "strava": "Strava",
        "nytimes": "The New York Times", "economist": "The Economist",
        // Telco (Singapore-first)
        "singtel": "Singtel", "starhub": "StarHub", "gomo": "GOMO",
        "circles": "Circles.Life", "simba": "Simba", "m1": "M1"
    ]
}
