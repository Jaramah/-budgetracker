import SwiftUI

/// A branded, self-contained card rendered to an image for sharing a month's
/// spending breakdown. Designed for `ImageRenderer` — it carries its own
/// background and fixed size, so it looks right off-screen.
struct AnalyticsShareCard: View {
    let monthLabel: String
    let spentCents: Int
    let slices: [(color: Color, value: Int)]
    let legend: [(name: String, cents: Int, color: Color)]

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 4) {
                Text("SPENDING BY CATEGORY")
                    .font(.caption.weight(.semibold)).tracking(1.5)
                    .foregroundStyle(DS.accentSoft)
                Text(monthLabel)
                    .font(.title2.bold()).foregroundStyle(DS.inkPrimary)
            }

            CategoryDonut(slices: slices, lineWidth: 24,
                          centerTop: "Spent", centerBottom: Money.string(spentCents))
                .frame(width: 190, height: 190)

            VStack(spacing: 12) {
                ForEach(Array(legend.prefix(5).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10) {
                        Circle().fill(item.color).frame(width: 10, height: 10)
                        Text(item.name).font(.subheadline).foregroundStyle(DS.inkSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text(Money.string(item.cents))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(DS.inkPrimary)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(DS.accent)
                Text("Tracked privately with **Budget**")
                    .font(.caption).foregroundStyle(DS.inkTertiary)
                Spacer()
                Text("on-device budgeting")
                    .font(.caption2).foregroundStyle(DS.inkTertiary)
            }
        }
        .padding(28)
        .frame(width: 380, height: 520)
        .background(
            LinearGradient(colors: [DS.bgBase, Color(hex: "#0B1220")],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}
