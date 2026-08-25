import SwiftUI

/// How to have bank alert messages logged automatically.
///
/// The setup lives with the user, not the app, and this screen says why. iOS gives
/// apps no way to read messages, so the only route to "automatic" is a Shortcuts
/// personal automation the user creates, scopes to the senders they choose, and
/// can remove whenever they like. Being straight about that is also what keeps the
/// feature honest: the app is never reading anything on its own.
struct SMSAutomationSetupView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String)] = [
        ("Open the Shortcuts app",
         "Go to the Automation tab and tap ＋ to create a Personal Automation."),
        ("Choose “Message”",
         "Set “Sender contains” to your bank's SMS ID — DBS, OCBC, UOB — or “Message contains” PayNow. Scoping it to your bank keeps unrelated texts out."),
        ("Add the action “Log Bank Alert”",
         "Search for it by name. Pass the message's Content as the Message input."),
        ("Turn off “Ask Before Running”",
         "This is what makes it automatic. Leave it on if you'd rather confirm each one.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AuroraCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your messages stay private", systemImage: "lock.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DS.inkPrimary)
                            Text("iOS doesn't let any app read your messages, and this one doesn't try. The automation below is yours: it runs on your phone, only for the senders you pick, and you can delete it at any time.")
                                .font(.caption).foregroundStyle(DS.inkSecondary)
                        }
                    }

                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        AuroraCard {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(DS.accent)
                                    .frame(width: 24, height: 24)
                                    .background(DS.accentDim, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(step.0).font(.subheadline.weight(.medium))
                                        .foregroundStyle(DS.inkPrimary)
                                    Text(step.1).font(.caption).foregroundStyle(DS.inkTertiary)
                                }
                            }
                        }
                    }

                    AuroraCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What gets logged").font(.subheadline.weight(.semibold))
                                .foregroundStyle(DS.inkPrimary)
                            Text("PayNow sent and received, and card charge alerts. Anything without an amount and payment wording is ignored, so one-time passcodes and ordinary texts never become transactions. The same alert arriving twice is only logged once.")
                                .font(.caption).foregroundStyle(DS.inkTertiary)
                        }
                    }

                    AuroraCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Prefer to do it by hand?").font(.subheadline.weight(.semibold))
                                .foregroundStyle(DS.inkPrimary)
                            Text("Copy the alert in Messages, then tap “Paste bank SMS” when adding a transaction. Same parsing, nothing to set up.")
                                .font(.caption).foregroundStyle(DS.inkTertiary)
                        }
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 16)
            }
            .auroraBackground()
            .navigationTitle("Log bank alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
