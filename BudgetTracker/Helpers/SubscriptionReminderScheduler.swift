import Foundation
import UserNotifications

/// Schedules local "renews soon — cancel if unused" reminders for active
/// subscriptions, `reminderLeadDays` before each renewal. Pure `UserNotifications`,
/// no server. Identifiers are namespaced by subscription id so we can cleanly
/// cancel/reschedule on any change.
enum SubscriptionReminderScheduler {

    private static let prefix = "sub."
    /// How many upcoming renewals to keep queued per subscription.
    private static let occurrencesAhead = 6

    /// Ask for notification permission (call when the user enables a reminder).
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch { return false }
    }

    /// Rebuild all subscription reminders from the current set.
    static func reschedule(subscriptions: [Subscription]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            for sub in subscriptions where sub.status == .active && sub.reminderEnabled {
                schedule(sub, center: center)
            }
        }
    }

    /// Cancel reminders for a single subscription (e.g. on delete/cancel).
    static func cancel(subID: UUID) {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<occurrencesAhead).map { id(subID, offset: $0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Internals

    private static func id(_ subID: UUID, offset: Int) -> String {
        "\(prefix)\(subID.uuidString).\(offset)"
    }

    private static func schedule(_ sub: Subscription, center: UNUserNotificationCenter) {
        let cal = DateHelpers.calendar
        let now = Date()
        let lead = max(0, sub.reminderLeadDays)

        // Walk forward one renewal at a time, scheduling a one-off reminder `lead`
        // days before each, for the next several cycles.
        var renewal = sub.nextRenewal(after: now)
        for offset in 0..<occurrencesAhead {
            defer { renewal = advance(renewal, cycle: sub.cycle, cal: cal) }

            guard let fireDate = cal.date(byAdding: .day, value: -lead, to: renewal),
                  let fireAt = at9am(fireDate, cal: cal),
                  fireAt > now else { continue }

            var comps = cal.dateComponents([.year, .month, .day, .hour], from: fireAt)
            comps.timeZone = cal.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let content = UNMutableNotificationContent()
            content.title = "\(sub.name) renews soon"
            let when = lead == 0 ? "today"
                     : lead == 1 ? "tomorrow"
                     : "in \(lead) days"
            content.body = "\(sub.name) renews \(when) for \(Money.string(sub.amountCents)). Cancel now if you no longer use it."
            content.sound = .default

            let request = UNNotificationRequest(identifier: id(sub.id, offset: offset),
                                                content: content, trigger: trigger)
            center.add(request, withCompletionHandler: nil)
        }
    }

    private static func advance(_ date: Date, cycle: Subscription.Cycle, cal: Calendar) -> Date {
        switch cycle {
        case .weekly:  return cal.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly:  return cal.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }

    private static func at9am(_ date: Date, cal: Calendar) -> Date? {
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = 9
        comps.timeZone = cal.timeZone
        return cal.date(from: comps)
    }
}
