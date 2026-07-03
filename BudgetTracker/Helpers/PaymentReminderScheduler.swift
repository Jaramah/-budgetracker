import Foundation
import UserNotifications

/// Schedules local notifications for credit-card payment due dates.
///
/// No server, no third-party libs — pure `UserNotifications`. Each card with a
/// `paymentDueDay` and `reminderEnabled` gets a repeating monthly reminder,
/// fired `leadDays` before the due day (and optionally on the day itself).
///
/// Identifiers are namespaced by card id so we can cancel/reschedule cleanly
/// whenever a card is added, edited, or deleted.
enum PaymentReminderScheduler {

    private static let prefix = "cardDue."

    /// Whether the user has globally enabled due-date reminders.
    static var globallyEnabled: Bool {
        UserDefaults.standard.object(forKey: "dueRemindersEnabled") as? Bool ?? true
    }

    /// Days before the due date to fire the reminder (default 3).
    static var leadDays: Int {
        let v = UserDefaults.standard.object(forKey: "dueReminderLeadDays") as? Int
        return v ?? 3
    }

    /// Ask for permission. Safe to call from a Settings action (not on launch).
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Rebuild all reminders from the current set of cards. Call after any card
    /// change or after the global toggle / lead-days setting changes.
    static func reschedule(cards: [CreditCardAccount]) {
        let center = UNUserNotificationCenter.current()
        // Clear everything we own, then re-add.
        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            guard globallyEnabled else { return }

            for card in cards where card.reminderEnabled && card.hasDueDay {
                scheduleReminders(for: card, center: center)
            }
        }
    }

    /// Cancel reminders for a single card (e.g. on delete).
    static func cancel(cardID: UUID) {
        let center = UNUserNotificationCenter.current()
        var ids = [dayID(cardID)]
        for offset in 0..<leadMonthsAhead { ids.append(leadID(cardID, offset: offset)) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Internals

    /// How many months of lead reminders to keep queued at once. `reschedule()`
    /// is already called on every card add/edit/delete and settings change, so
    /// this window keeps replenishing itself in practice.
    private static let leadMonthsAhead = 6

    private static func leadID(_ id: UUID, offset: Int) -> String { "\(prefix)\(id.uuidString).lead.\(offset)" }
    private static func dayID(_ id: UUID) -> String { "\(prefix)\(id.uuidString).day" }

    private static func scheduleReminders(for card: CreditCardAccount,
                                          center: UNUserNotificationCenter) {
        let cal = DateHelpers.calendar
        let dueDay = min(max(card.paymentDueDay, 1), 28)

        // Day-of reminder: a single repeating monthly trigger is safe here
        // since dueDay is always a valid day-of-month (1...28).
        add(id: dayID(card.id),
            title: "Card payment due today",
            body: "\(card.displayName) payment is due today.",
            day: dueDay, hour: 9, cal: cal, center: center)

        // Lead reminder: a single repeating "day N of every month" trigger
        // cannot correctly represent "leadDays before the due day" — when
        // leadDays >= dueDay, that lands in the *previous* month on a day
        // that varies with month length (e.g. 3 days before the 2nd is the
        // 27th-30th of the month before, not a fixed day-of-month). Schedule
        // concrete one-off dates for the next several months instead, each
        // computed with real calendar arithmetic off that month's actual due date.
        guard leadDays > 0 else { return }
        let body = leadDays == 1
            ? "\(card.displayName) payment is due tomorrow."
            : "\(card.displayName) payment is due in \(leadDays) days."
        let now = Date()

        for offset in 0..<leadMonthsAhead {
            guard let monthDate = cal.date(byAdding: .month, value: offset, to: now) else { continue }
            var dueComps = cal.dateComponents([.year, .month], from: monthDate)
            let daysInMonth = cal.range(of: .day, in: .month, for: monthDate)?.count ?? dueDay
            dueComps.day = min(dueDay, daysInMonth)
            dueComps.hour = 9
            guard let dueDate = cal.date(from: dueComps),
                  let leadDate = cal.date(byAdding: .day, value: -leadDays, to: dueDate),
                  leadDate > now
            else { continue }

            var fireComps = cal.dateComponents([.year, .month, .day, .hour], from: leadDate)
            fireComps.timeZone = cal.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: fireComps, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = "Card payment due soon"
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: leadID(card.id, offset: offset),
                                                 content: content, trigger: trigger)
            center.add(request, withCompletionHandler: nil)
        }
    }

    private static func add(id: String, title: String, body: String,
                            day: Int, hour: Int,
                            cal: Calendar, center: UNUserNotificationCenter) {
        var comps = DateComponents()
        comps.day = day
        comps.hour = hour
        comps.timeZone = cal.timeZone   // Asia/Singapore
        // No year/month → repeats monthly on that day.
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }
}
