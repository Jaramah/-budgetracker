import SwiftUI
import SwiftData

/// Root shell: the reference's tab layout with a prominent center "+" add button.
/// Home · Activity · [+] · Budget · Accounts · Settings.
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tab = 0
    @State private var showAdd = false
    @State private var showBills = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Active screen
            Group {
                switch tab {
                case 0: HomeView(
                            onSeeAllActivity: { tab = 1 },
                            onSeeBills: { showBills = true },
                            onSeeCategories: { tab = 2 })
                case 1: ActivityView()
                case 2: BudgetView()
                case 3: AccountsView()
                default: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .auroraBackground()
        .sheet(isPresented: $showAdd) { AddTransactionView() }
        .sheet(isPresented: $showBills) { BillsView() }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(0, "house.fill", "Home")
            tabButton(1, "list.bullet", "Activity")
            addButton
            tabButton(2, "chart.pie.fill", "Budget")
            tabButton(3, "creditcard.fill", "Cards")
            tabButton(4, "gearshape.fill", "Settings")
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
