import Foundation

/// Maps a statement line's merchant description to one of the user's existing
/// categories using keyword rules. Keeps a built-in merchant dictionary, but
/// always resolves to a *real* Category the user has (by fuzzy name match),
/// so it adapts to whatever categories exist.
enum AutoCategorizer {

    /// Built-in merchant keyword → canonical category-name hints.
    /// The value is matched against the user's actual category names (case-insensitive,
    /// substring both ways), so "Food" hint will hit a "Food & Dining" category.
    private static let rules: [(keywords: [String], categoryHint: String)] = [
        (["grab", "gojek", "comfort", "taxi", "mrt", "smrt", "bus", "transit", "ez-link", "ezlink", "shell", "esso", "caltex", "spc", "petrol", "parking", "season parking"], "Transport"),
        (["fairprice", "ntuc", "cold storage", "giant", "sheng siong", "shengsiong", "redmart", "grocer", "market", "supermarket", "don don", "donki"], "Groceries"),
        (["mcdonald", "kfc", "burger", "starbucks", "coffee", "kopitiam", "restaurant", "cafe", "food", "dining", "eatery", "subway", "pizza", "din tai", "toast box", "ya kun", "deliveroo", "foodpanda", "chatime", "bubble tea"], "Food & Dining"),
        (["netflix", "spotify", "disney", "hbo", "youtube", "cinema", "golden village", "cathay", "shaw", "steam", "playstation", "xbox", "nintendo", "game", "concert", "ticket"], "Entertainment"),
        (["amazon", "shopee", "lazada", "qoo10", "taobao", "uniqlo", "zara", "h&m", "shop", "store", "mall", "apple.com", "apple store", "ikea", "challenger", "courts", "best denki"], "Shopping"),
        (["singtel", "gomo", "starhub", "m1", "circles", "simba", "myrepublic", "sp group", "sp services", "utility", "electric", "water", "gas", "wifi", "broadband", "town council", "conservancy"], "Utilities"),
        (["clinic", "hospital", "pharmacy", "guardian", "watson", "unity", "dental", "doctor", "medical", "health", "polyclinic", "raffles medical"], "Health"),
        (["rent", "mortgage", "hdb", "condo", "property", "landlord", "housing"], "Housing"),
        (["salary", "payroll", "refund", "interest", "dividend", "cashback", "rebate", "payment received", "thank you"], "Income")
    ]

    /// Pick the best-matching category for a description from the given list.
    /// Returns nil if nothing matches confidently (caller leaves it uncategorized).
    static func category(for description: String, from categories: [Category]) -> Category? {
        let desc = description.lowercased()
        guard !categories.isEmpty else { return nil }

        // 1) Direct hit: the description literally contains a category's name.
        for cat in categories {
            let name = cat.name.lowercased()
            if !name.isEmpty, desc.contains(name) { return cat }
            // Also match the first word of the category (e.g. "Food" from "Food & Dining").
            if let firstWord = name.split(separator: " ").first.map(String.init),
               firstWord.count >= 4, desc.contains(firstWord) {
                return cat
            }
        }

        // 2) Keyword rules → resolve the hint to a real category by name.
        for rule in rules where rule.keywords.contains(where: { desc.contains($0) }) {
            if let match = resolve(hint: rule.categoryHint, in: categories) {
                return match
            }
        }
        return nil
    }

    /// Find the user's category whose name best matches a hint, substring either way.
    private static func resolve(hint: String, in categories: [Category]) -> Category? {
        let h = hint.lowercased()
        // Exact-ish first.
        if let exact = categories.first(where: { $0.name.lowercased() == h }) { return exact }
        // Substring either direction (handles "Food" hint vs "Food & Dining" category).
        if let contains = categories.first(where: {
            let n = $0.name.lowercased()
            return n.contains(h) || h.contains(n)
        }) { return contains }
        // First word match.
        let hFirst = h.split(separator: " ").first.map(String.init) ?? h
        return categories.first(where: { $0.name.lowercased().contains(hFirst) })
    }
}
