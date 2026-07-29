import SwiftUI
import SwiftData

@main
struct BudgetTrackerApp: App {
    let container: ModelContainer
    @StateObject private var appState = AppState()
    @StateObject private var lock = AppLock()
    @StateObject private var store = ProStore()
    @StateObject private var theme = ThemeManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([
            Category.self,
            Transaction.self,
            StatementImport.self,
            StatementLine.self,
            CreditCardAccount.self,
            RecurringRule.self,
            Goal.self,
            Bill.self,
            Subscription.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Self-heal: wipe an incompatible on-disk store rather than crashing.
            BudgetTrackerApp.deleteStoreFiles()
            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer even after reset: \(error)")
            }
        }
    }

    private static func deleteStoreFiles() {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(appState)
                    .environmentObject(store)
                    .environmentObject(theme)
                    .task {
                        await SampleData.seedIfNeeded(container.mainContext)
                        DemoSeed.seedIfNeeded(container.mainContext)   // no-op unless DEMO_SEED=1
                        RecurringMaterializer.run(context: container.mainContext)

                        // Detect subscriptions from imported transactions and keep
                        // their renewal reminders scheduled.
                        let ctx = container.mainContext
                        let txs = (try? ctx.fetch(FetchDescriptor<Transaction>())) ?? []
                        SubscriptionDetector.refresh(transactions: txs, context: ctx)
                        let subs = (try? ctx.fetch(FetchDescriptor<Subscription>())) ?? []
                        SubscriptionReminderScheduler.reschedule(subscriptions: subs)
                    }
                    .task {
                        // Free users see ads; ask ATT + start the SDK once Pro state is known.
                        await AdsBootstrap.start(isPro: store.isPro)
                    }
                if lock.isLocked {
                    LockScreenView { lock.authenticate() }
                        .transition(.opacity)
                }
            }
            // Was hard-coded to .dark. Light themes need the system chrome —
            // status bar, keyboards, pickers — to follow the palette too.
            .preferredColorScheme(theme.current.colorScheme)
            .tint(DS.accent)
            .onAppear { lock.authenticate() }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive: lock.lockIfNeeded()
            case .active where lock.isLocked: lock.authenticate()
            default: break
            }
        }
    }
}
