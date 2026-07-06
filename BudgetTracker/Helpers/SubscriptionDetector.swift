import Foundation
import SwiftData

/// Finds likely subscriptions in the user's transactions and upserts them as
/// `.suggested` for one-tap confirmation.
///
/// Two signals:
/// 1. **Known brand** — a merchant in `knownBrands` (Netflix, Spotify, telco…) is
///    flagged even from a single charge.
/// 2. **Recurring pattern** — any merchant charged ≥2 times at a regular interval
///    with a stable amount.
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

        var added = 0
        for (key, txs) in groups {
            guard !knownKeys.contains(key) else { continue }
            guard let candidate = evaluate(key: key, txs: txs) else { continue }
            context.insert(candidate)
            knownKeys.insert(key)
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    /// Normalised, stable merchant token — the first meaningful word, lowercased.
    /// e.g. "SPOTIFY P42A314ACB STOCKHOLM SE" → "spotify", "NETFLIX.COM" → "netflix".
    static func matchKey(for note: String) -> String? {
        let tokens = note.lowercased().split { !$0.isLetter }.map(String.init)
        for t in tokens where t.count >= 2 && !noiseTokens.contains(t) {
            return t
        }
        return nil
    }

    // MARK: Heuristics

    private static func evaluate(key: String, txs: [Transaction]) -> Subscription? {
        let sorted = txs.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }

        let cadence = inferCycle(sorted)

        // Trusted, unambiguous subscription brand — flag even from one charge.
        if let brand = knownBrands[key], !ambiguousBrands.contains(key) {
            return make(name: brand, key: key, latest: latest, cycle: cadence ?? .monthly)
        }

        // Everything else (unknown merchants + ambiguous retail brands like Apple/
        // Amazon that also sell one-off) needs a genuine recurring pattern.
        guard sorted.count >= 2, let cadence, amountsStable(sorted) else { return nil }
        return make(name: knownBrands[key] ?? key.capitalized, key: key, latest: latest, cycle: cadence)
    }

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
