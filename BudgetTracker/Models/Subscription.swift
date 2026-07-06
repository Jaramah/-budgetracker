import Foundation
import SwiftData

/// A recurring subscription (Netflix, Spotify, iCloud, telco…) surfaced from the
/// user's statements or added manually. Distinct from `Bill` (a manual due-date
/// reminder) and `RecurringRule` (auto-posts transactions): a `Subscription` is a
/// tracked ongoing charge with an optional "cancel before renewal" reminder.
///
/// A Pro feature. Money in integer cents (see `Money`).
@Model
final class Subscription {
    var id: UUID
    /// Display name, e.g. "Netflix".
    var name: String
    /// Normalised merchant token used to match transactions and dedupe suggestions
    /// (e.g. "netflix"). Stable across statement formatting differences.
    var matchKey: String
    var amountCents: Int
    /// Raw `Cycle` value.
    var cycleRaw: String
    /// A real charge date (detected) or user-chosen date; renewals are computed
    /// forward from here.
    var anchorDate: Date
    /// Optional card this subscription is billed to.
    var cardID: UUID?
    /// Optional category link (nullify on delete — mirrors Transaction).
    var category: Category?
    /// Whether a cancel/renewal reminder is scheduled.
    var reminderEnabled: Bool
    /// Days before the renewal date to fire the reminder.
    var reminderLeadDays: Int
    /// Raw `Status` value.
    var statusRaw: String
    /// True if the user added it by hand (vs auto-detected).
    var createdManually: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        matchKey: String,
        amountCents: Int,
        cycle: Cycle = .monthly,
        anchorDate: Date = .now,
        cardID: UUID? = nil,
        category: Category? = nil,
        reminderEnabled: Bool = true,
        reminderLeadDays: Int = 3,
        status: Status = .suggested,
        createdManually: Bool = false
    ) {
        self.id = id
        self.name = name
        self.matchKey = matchKey
        self.amountCents = abs(amountCents)
        self.cycleRaw = cycle.rawValue
        self.anchorDate = anchorDate
        self.cardID = cardID
        self.category = category
        self.reminderEnabled = reminderEnabled
        self.reminderLeadDays = reminderLeadDays
        self.statusRaw = status.rawValue
        self.createdManually = createdManually
        self.updatedAt = .now
    }

    var cycle: Cycle {
        get { Cycle(rawValue: cycleRaw) ?? .monthly }
        set { cycleRaw = newValue.rawValue }
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .suggested }
        set { statusRaw = newValue.rawValue }
    }

    /// Cost normalised to a monthly figure, so totals mix cycles correctly.
    var monthlyEquivalentCents: Int {
        switch cycle {
        case .weekly:  return (amountCents * 52) / 12
        case .monthly: return amountCents
        case .yearly:  return amountCents / 12
        }
    }

    /// The next renewal/charge date on or after today, rolled forward from `anchorDate`.
    func nextRenewal(after now: Date = .now) -> Date {
        let cal = DateHelpers.calendar
        let today = cal.startOfDay(for: now)
        var d = anchorDate
        var guardCount = 0
        let (comp, step): (Calendar.Component, Int) = {
            switch cycle {
            case .weekly:  return (.day, 7)
            case .monthly: return (.month, 1)
            case .yearly:  return (.year, 1)
            }
        }()
        while d < today && guardCount < 600 {
            d = cal.date(byAdding: comp, value: step, to: d) ?? d
            guardCount += 1
        }
        return d
    }

    enum Cycle: String, CaseIterable, Identifiable, Codable {
        case weekly, monthly, yearly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .weekly:  return "Weekly"
            case .monthly: return "Monthly"
            case .yearly:  return "Yearly"
            }
        }
        /// Short "/mo", "/yr" style suffix.
        var perLabel: String {
            switch self {
            case .weekly:  return "/wk"
            case .monthly: return "/mo"
            case .yearly:  return "/yr"
            }
        }
    }

    enum Status: String, Codable {
        /// Auto-detected, awaiting the user's confirmation. Counts toward the teaser.
        case suggested
        /// Confirmed by the user (or added manually) — eligible for reminders.
        case active
        /// User marked it cancelled — kept for history, no reminders.
        case cancelled
        /// User rejected the suggestion — never re-suggest this merchant.
        case dismissed
    }
}
