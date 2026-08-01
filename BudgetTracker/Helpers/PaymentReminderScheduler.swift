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
        var ids: [String] = []
        for offset in 0..<leadMonthsAhead {
            ids.append(leadID(cardID, offset: offset))
            ids.append(dayID(cardID, offset: offset))
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Internals

    /// How many months of lead reminders to keep queued at once. `reschedule()`
    /// is already called on every card add/edit/delete and settings change, so
    /// this window keeps replenishing itself in practice.
    private static let leadMonthsAhead = 6

    private static func leadID(_ id: UUID, offset: Int) -> String { "\(prefix)\(id.uuidString).lead.\(offset)" }
    private static func dayID(_ id: UUID, offset: Int) -> String { "\(prefix)\(id.uuidString).day.\(offset)" }

    private static func scheduleReminders(for card: CreditCardAccount,
                                          center: UNUserNotificationCenter) {
        let now = Date()

        // Both reminders are scheduled as concrete one-off dates, one per month.
        //
        // A repeating "day N of every month" trigger cannot express either of them.
        // For the day-of reminder it silently never fires in months that lack that
        // day — a card due on the 31st would go unremembered in February, April,
        // June, September and November. For the lead reminder it is wrong whenever
        // leadDays >= dueDay, since "3 days before the 2nd" is a varying day of the
        // *previous* month.
        //
        // `card.nextDueDate` already clamps the due day to each month's real length,
        // so a 31st cycle lands on the 28th/29th in February instead of vanishing.
        let body = leadDays == 1
            ? "\(card.displayName) payment is due tomorrow."
            : "\(card.displayName) payment is due in \(leadDays) days."

        let cal = DateHelpers.calendar
        for offset in 0..<leadMonthsAhead {
            guard let monthAnchor = cal.date(byAdding: .month, value: offset, to: now),
                  let dueDate = card.nextDueDate(asOf: cal.startOfDay(for: monthAnchor))
            else { continue }

            if dueDate > now {
                schedule(id: dayID(card.id, offset: offset),
                         title: "Card payment due today",
                         body: "\(card.displayName) payment is due today.",
                         at: dueDate, cal: cal, center: center)
            }

            guard leadDays > 0,
                  let leadDate = cal.date(byAdding: .day, value: -leadDays, to: dueDate),
                  leadDate > now
            else { continue }

            schedule(id: leadID(card.id, offset: offset),
                     title: "Card payment due soon",
                     body: body,
                     at: leadDate, cal: cal, center: center)
        }
    }

    /// Schedule a one-off notification at a concrete date.
    private static func schedule(id: String, title: String, body: String,
                                 at date: Date, cal: Calendar,
                                 center: UNUserNotificationCenter) {
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        comps.timeZone = cal.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger),
                   withCompletionHandler: nil)
    }

}
