import SwiftUI
import SwiftData

/// Settings tab — matches the Aurora dark-fintech look. Grouped cards for:
/// General (currency), Security (Face ID lock), Notifications (payment-due
/// reminders + lead time), Manage (categories, recurring rules), Data
/// (CSV export, erase all), and About.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: ProStore

    // Cards drive the notification rescheduling when reminder settings change.
    @Query(sort: \CreditCardAccount.sortIndex) private var cards: [CreditCardAccount]
    @Query private var transactions: [Transaction]

    // Persisted settings.
    @AppStorage("currencyCode") private var currencyCode: String = "SGD"
    @AppStorage("appLockEnabled") private var appLockEnabled: Bool = false
    @AppStorage("dueRemindersEnabled") private var dueRemindersEnabled: Bool = true
    @AppStorage("dueReminderLeadDays") private var leadDays: Int = 3

    // Sheets / dialogs.
    @State private var showCurrencyPicker = false
    @State private var showCategories = false
    @State private var showRecurring = false
    @State private var showShare = false
    @State private var shareURL: URL?
    @State private var showEraseConfirm = false
    @State private var eraseDoneMessage: String?
    @State private var showPaywall = false
    @State private var restoreMessage: String?

    private var currencyLabel: String {
        CurrencyOption.common.first { $0.code == currencyCode }?.label ?? currencyCode
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    proCard
                    generalCard
                    securityCard
                    notificationsCard
                    manageCard
                    dataCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120) // clear the tab bar
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .auroraBackground()
            .scrollContentBackground(.hidden)
            .toolbarBackground(DS.bgBase, for: .navigationBar)
        }
        .tint(DS.accent)
        // Pro upgrade
        .sheet(isPresented: $showPaywall) { PaywallView() }
        // Currency picker
        .sheet(isPresented: $showCurrencyPicker) {
            CurrencyPickerView(selected: $currencyCode)
        }
        // Category manager
        .sheet(isPresented: $showCategories) {
            CategoryManagerView()
        }
        // Recurring rules manager
        .sheet(isPresented: $showRecurring) {
            RecurringRulesView()
        }
        // Share sheet for CSV export
        .sheet(isPresented: $showShare) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
        // Erase confirmation
        .confirmationDialog("Erase all data?",
                            isPresented: $showEraseConfirm, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { eraseAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all transactions, cards, goals, bills, recurring rules and categories on this device. This cannot be undone.")
        }
        .alert("Done", isPresented: .constant(eraseDoneMessage != nil)) {
            Button("OK") { eraseDoneMessage = nil }
        } message: {
            Text(eraseDoneMessage ?? "")
        }
        .alert("Restore Purchases", isPresented: .constant(restoreMessage != nil)) {
            Button("OK") { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    // MARK: - Pro

    @ViewBuilder
    private var proCard: some View {
        if store.isPro {
            SettingsCard(title: "Budget Pro") {
                HStack {
                    SettingsLabel(icon: "crown.fill", tint: DS.accent,
                                  title: "Pro unlocked",
                                  subtitle: "Unlimited cards · No ads · Thank you!")
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(DS.moneyIn)
                }
            }
        } else {
            SettingsCard(title: "Budget Pro") {
                Button { showPaywall = true } label: {
                    HStack {
                        SettingsLabel(icon: "crown.fill", tint: DS.accent,
                                      title: "Unlock Pro",
                                      subtitle: "Unlimited cards and remove ads")
                        Spacer()
                        if !store.priceText.isEmpty {
                            Text(store.priceText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DS.accentSoft)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.inkTertiary)
                    }
                }
                .buttonStyle(.plain)
                Divider().overlay(DS.hairline)
                SettingsRow(icon: "arrow.clockwise", tint: DS.accentSoft,
                            title: "Restore Purchases", value: nil) {
                    Task {
                        let ok = await store.restore()
                        restoreMessage = ok
                            ? "Your Pro purchase has been restored."
                            : "No previous purchase was found on this Apple ID."
                    }
                }
            }
        }
    }

    // MARK: - General

    private var generalCard: some View {
        SettingsCard(title: "General") {
            SettingsRow(icon: "dollarsign.circle.fill", tint: DS.accent,
                        title: "Currency", value: currencyCode) {
                showCurrencyPicker = true
            }
        }
    }

    // MARK: - Security

    private var securityCard: some View {
        SettingsCard(title: "Security") {
            Toggle(isOn: Binding(
                get: { appLockEnabled },
                set: { newValue in
                    if newValue && !AppLock.biometricsAvailable {
                        // No biometrics/passcode enrolled — don't lock the user out.
                        appLockEnabled = false
                    } else {
                        appLockEnabled = newValue
                    }
                    Haptics.tap()
                }
            )) {
                SettingsLabel(icon: "faceid", tint: DS.accentSoft,
                              title: "Lock with \(AppLock.biometryLabel)",
                              subtitle: AppLock.biometricsAvailable
                                  ? "Require authentication to open the app"
                                  : "Set up Face ID / passcode in iOS Settings first")
            }
            .tint(DS.accent)
            .disabled(!AppLock.biometricsAvailable)
        }
    }

    // MARK: - Notifications

    private var notificationsCard: some View {
        SettingsCard(title: "Notifications") {
            Toggle(isOn: Binding(
                get: { dueRemindersEnabled },
                set: { newValue in
                    dueRemindersEnabled = newValue
                    Haptics.tap()
                    Task {
                        if newValue { _ = await PaymentReminderScheduler.requestAuthorization() }
                        PaymentReminderScheduler.reschedule(cards: cards)
                    }
                }
            )) {
                SettingsLabel(icon: "bell.badge.fill", tint: DS.warning,
                              title: "Card payment reminders",
                              subtitle: "Alerts before each card's due date")
            }
            .tint(DS.accent)

            if dueRemindersEnabled {
                Divider().overlay(DS.hairline)
                HStack {
                    SettingsLabel(icon: "clock.fill", tint: DS.accentSoft,
                                  title: "Remind me", subtitle: nil)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { leadDays },
                        set: { leadDays = $0; PaymentReminderScheduler.reschedule(cards: cards) }
                    )) {
                        Text("On the day").tag(0)
                        Text("1 day before").tag(1)
                        Text("2 days before").tag(2)
                        Text("3 days before").tag(3)
                        Text("5 days before").tag(5)
                        Text("7 days before").tag(7)
                    }
                    .pickerStyle(.menu)
                    .tint(DS.accentSoft)
                }
            }
        }
    }

    // MARK: - Manage

    private var manageCard: some View {
        SettingsCard(title: "Manage") {
            SettingsRow(icon: "square.grid.2x2.fill", tint: DS.accent,
                        title: "Categories", value: nil) { showCategories = true }
            Divider().overlay(DS.hairline)
            SettingsRow(icon: "arrow.triangle.2.circlepath", tint: DS.moneyIn,
                        title: "Recurring rules", value: nil) { showRecurring = true }
        }
    }

    // MARK: - Data

    private var dataCard: some View {
        SettingsCard(title: "Data") {
            SettingsRow(icon: "square.and.arrow.up.fill", tint: DS.accentSoft,
                        title: "Export as CSV", value: nil) { exportCSV() }
            Divider().overlay(DS.hairline)
            SettingsRow(icon: "trash.fill", tint: DS.moneyOut,
                        title: "Erase all data", value: nil, destructive: true) {
                showEraseConfirm = true
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        SettingsCard(title: "About") {
            HStack {
                SettingsLabel(icon: "info.circle.fill", tint: DS.inkTertiary,
                              title: "Version", subtitle: nil)
                Spacer()
                Text(appVersion).foregroundStyle(DS.inkTertiary)
            }
            Divider().overlay(DS.hairline)
            HStack {
                SettingsLabel(icon: "lock.shield.fill", tint: DS.moneyIn,
                              title: "Private by design", subtitle: "All data stays on this device")
                Spacer()
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: - Actions

    private func exportCSV() {
        if let url = CSVExporter.exportTransactions(transactions) {
            shareURL = url
            showShare = true
            Haptics.success()
        } else {
            Haptics.warning()
        }
    }

    private func eraseAllData() {
        // Delete every model type. Order doesn't matter — relationships nullify.
        for t in transactions { context.delete(t) }
        deleteAll(CreditCardAccount.self)
        deleteAll(Goal.self)
        deleteAll(Bill.self)
        deleteAll(RecurringRule.self)
        deleteAll(StatementImport.self)
        deleteAll(StatementLine.self)
        deleteAll(Category.self)
        try? context.save()
        PaymentReminderScheduler.reschedule(cards: [])
        Haptics.success()
        eraseDoneMessage = "All data has been erased. Restart the app to reseed default categories."
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        if let rows = try? context.fetch(FetchDescriptor<T>()) {
            for r in rows { context.delete(r) }
        }
    }
}

// MARK: - Reusable Settings building blocks

/// A titled card wrapping a group of setting rows (Aurora styling).
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.inkTertiary)
                .padding(.leading, 4)
            VStack(spacing: 12) { content }
                .padding(DS.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.bgCard, in: RoundedRectangle(cornerRadius: DS.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.corner, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 1))
        }
    }
}

/// Icon + title (+ optional subtitle) used inside toggles and rows.
struct SettingsLabel: View {
    let icon: String
    var tint: Color = DS.accent
    let title: String
    var subtitle: String?
    var destructive: Bool = false
    var body: some View {
        HStack(spacing: 12) {
            IconChip(symbol: icon, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(destructive ? DS.moneyOut : DS.inkPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DS.inkTertiary)
                }
            }
        }
    }
}

/// A tappable settings row with a chevron and optional trailing value.
struct SettingsRow: View {
    let icon: String
    var tint: Color = DS.accent
    let title: String
    var value: String?
    var destructive: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                SettingsLabel(icon: icon, tint: tint, title: title, subtitle: nil,
                              destructive: destructive)
                Spacer()
                if let value {
                    Text(value).foregroundStyle(DS.inkTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.inkTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Currency picker

struct CurrencyPickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(CurrencyOption.common) { opt in
                        Button {
                            selected = opt.code
                            Haptics.tap()
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opt.code).foregroundStyle(DS.inkPrimary)
                                        .fontWeight(.semibold)
                                    Text(opt.label).font(.caption)
                                        .foregroundStyle(DS.inkTertiary)
                                }
                                Spacer()
                                if selected == opt.code {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(DS.accent)
                                }
                            }
                            .padding(DS.cardPadding)
                            .background(DS.bgCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(selected == opt.code ? DS.accent : DS.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .auroraBackground()
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.tint(DS.accent)
                }
            }
        }
    }
}
