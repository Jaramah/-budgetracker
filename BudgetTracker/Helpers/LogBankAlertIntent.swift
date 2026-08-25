import AppIntents
import SwiftData

/// Logs a bank alert SMS, for use from a Shortcuts personal automation.
///
/// This is as close to automatic as iOS permits. Apps cannot read SMS, but the
/// *user* can set up an automation — "When I receive a message from DBS, run
/// Log Bank Alert" — which hands the text over. The app still never touches the
/// inbox; the automation is the user's own, scoped to senders they choose, and
/// removable by them at any time.
///
/// `openAppWhenRun` is false so the automation stays in the background: making
/// the app launch on every bank SMS would be worse than typing it in.
struct LogBankAlertIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Bank Alert"
    static var description = IntentDescription(
        "Reads a PayNow or card alert message and logs it as a transaction.",
        categoryName: "Transactions"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Message", description: "The bank alert text.")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log the bank alert \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SharedModelContainer.shared.mainContext
        switch SMSTransactionImporter.importAlert(text, context: context) {
        case .added(let summary), .duplicate(let summary):
            return .result(dialog: "\(summary)")
        case .notRecognised:
            // Fail loudly rather than silently doing nothing: an automation the
            // user believes is running should say when it isn't recording anything.
            throw AlertNotRecognised()
        }
    }
}

/// Surfaced in Shortcuts when the message isn't a bank alert.
struct AlertNotRecognised: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "That message doesn't look like a bank alert — no amount and payment wording were found, so nothing was logged."
    }
}

/// Makes the action discoverable in the Shortcuts app without the user hunting
/// for it, and gives Siri a phrase.
struct BudgetTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogBankAlertIntent(),
            phrases: ["Log a bank alert in \(.applicationName)"],
            shortTitle: "Log Bank Alert",
            systemImageName: "message.badge.filled.fill"
        )
    }
}
