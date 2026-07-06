import SwiftUI

/// App-wide UI state shared across tabs. Currently holds the selected month so
/// the Spending / Analysis / Budgets tabs all stay in sync — and so importing a
/// statement can jump every tab to that statement's month (fixes the "imported
/// transactions don't show up in Budgets" confusion when they're in another month).
@MainActor
final class AppState: ObservableObject {
    /// The month currently being viewed across all tabs (any day within it).
    @Published var selectedMonth: Date = .now

    /// Which segment the Cards tab shows: 0 = Cards, 1 = Budget, 2 = Goals.
    /// Lets Home deep-link to Budget now that it lives inside the Cards tab.
    @Published var accountsSegment: Int = 0

    /// Jump all tabs to the month containing `date`.
    func goToMonth(of date: Date) {
        selectedMonth = DateHelpers.startOfMonth(date)
    }
}
