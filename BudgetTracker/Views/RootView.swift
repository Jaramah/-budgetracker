import SwiftUI
import SwiftData

/// Root shell: the reference's tab layout with a prominent center "+" add button.
/// Home · Activity · [+] · Budget · Accounts · Settings.
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: ProStore
    @State private var tab = 0
    @State private var showAdd = false
    @State private var showBills = false
    @State private var showSubscriptions = false

    /// For marketing captures: `UI_SCREEN` (launch env) opens the app directly on a
    /// screen so each shot is a deterministic fresh launch, no in-app tapping. Absent
    /// in normal use, so this is a no-op in shipped builds.
    private static var launchScreen: String { ProcessInfo.processInfo.environment["UI_SCREEN"] ?? "" }

    init() {
        let initialTab: Int
        switch RootView.launchScreen {
        case "cards", "budget", "analytics": initialTab = 2
        case "activity":                     initialTab = 1
        case "settings":                     initialTab = 3
        default:                             initialTab = 0
        }
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Active screen
            Group {
                switch tab {
                case 0: HomeView(
                            onSeeAllActivity: { tab = 1 },
                            onSeeBills: { showBills = true },
                            onSeeCategories: { tab = 2; appState.accountsSegment = 1 },
                            onSeeSubscriptions: { showSubscriptions = true })
                case 1: ActivityView()
                case 2: AccountsView()
                default: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                // Free users see a banner ad above the tab bar; Pro removes it.
                if !store.isPro {
                    AdBannerSlot()
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(DS.bgCard)
                }
                tabBar
            }
        }
        .auroraBackground()
        .sheet(isPresented: $showAdd) { AddTransactionView() }
        .sheet(isPresented: $showBills) { BillsView() }
        .sheet(isPresented: $showSubscriptions) { SubscriptionsView() }
        .onAppear {
            switch RootView.launchScreen {
            case "cards":               appState.accountsSegment = 0
            case "budget", "analytics": appState.accountsSegment = 1
            case "subscriptions":       showSubscriptions = true
            default: break
            }
        }
        .task {
            // Marketing capture: `UI_DEMO_TOUR=1` auto-drives the app through its
            // screens for the App Preview recording. No-op in normal use.
            guard ProcessInfo.processInfo.environment["UI_DEMO_TOUR"] == "1" else { return }
            await runDemoTour()
        }
    }

    /// Programmatic, deterministic screen tour for recording an App Preview.
    private func runDemoTour() async {
        func hold(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        let steps: [(Int, Int)] = [
            (0, 0),   // Home hero + donut
            (2, 0),   // Cards wall
            (2, 1),   // Budget (spending-by-category / budgets)
            (1, 0),   // Activity list
            (3, 0),   // Settings
            (0, 0)    // back to Home
        ]
        await hold(3.0)
        for (t, seg) in steps.dropFirst() {
            withAnimation(.easeInOut(duration: 0.35)) {
                appState.accountsSegment = seg
                tab = t
            }
            await hold(3.0)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(0, "house.fill", "Home")
            tabButton(1, "list.bullet", "Activity")
            addButton
            tabButton(2, "creditcard.fill", "Cards")
            tabButton(3, "gearshape.fill", "Settings")
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 26)
        .background(
            DS.bgCard
                .overlay(Rectangle().fill(DS.hairline).frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ index: Int, _ symbol: String, _ label: String) -> some View {
        Button {
            tab = index; Haptics.tap()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 19))
                Text(label).font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(tab == index ? DS.accentSoft : DS.inkTertiary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button {
            showAdd = true; Haptics.tap()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(
                    LinearGradient(colors: [DS.accent, DS.accentSoft],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .shadow(color: DS.accent.opacity(0.5), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .offset(y: -8)
        .frame(maxWidth: .infinity)
    }
}
