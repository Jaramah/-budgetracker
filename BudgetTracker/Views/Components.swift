import SwiftUI

// MARK: - Section header ("Title" + optional "See all")
struct SectionHeader: View {
    let title: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(DS.inkPrimary)
            Spacer()
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .font(.subheadline)
                    .foregroundStyle(DS.accentSoft)
            }
        }
    }
}

// MARK: - Thin rounded progress bar (budget usage)
struct ProgressBar: View {
    /// 0...1
    let value: Double
    var tint: Color = DS.accent
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Money text (big tabular hero figure)
struct MoneyText: View {
    let cents: Int
    var size: CGFloat = 34
    var weight: Font.Weight = .bold
    var color: Color = DS.inkPrimary

    var body: some View {
        Text(Money.string(cents))
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

// MARK: - Category donut (ring with slices)
struct CategoryDonut: View {
    /// (color, amountCents) slices; drawn proportionally.
    let slices: [(color: Color, value: Int)]
    var lineWidth: CGFloat = 18
    var centerTop: String = ""
    var centerBottom: String = ""

    private var total: Int { max(1, slices.reduce(0) { $0 + $1.value }) }

    var body: some View {
        ZStack {
            ForEach(Array(cumulative().enumerated()), id: \.offset) { _, seg in
                Circle()
                    .trim(from: seg.start, to: seg.end)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            if slices.isEmpty {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            }
            VStack(spacing: 2) {
                if !centerTop.isEmpty {
                    Text(centerTop).font(.caption).foregroundStyle(DS.inkTertiary)
                }
                if !centerBottom.isEmpty {
                    Text(centerBottom)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DS.inkPrimary)
                }
            }
        }
    }

    private func cumulative() -> [(start: CGFloat, end: CGFloat, color: Color)] {
        var out: [(CGFloat, CGFloat, Color)] = []
        var acc: CGFloat = 0
        let gap: CGFloat = 0.006
        for s in slices where s.value > 0 {
            let frac = CGFloat(s.value) / CGFloat(total)
            let start = acc + gap
            let end = acc + frac - gap
            out.append((max(0, start), max(start, end), s.color))
            acc += frac
        }
        return out.map { ($0.0, $0.1, $0.2) }
    }
}

// MARK: - Icon chip (rounded square with SF Symbol on tinted bg)
struct IconChip: View {
    let symbol: String
    var tint: Color = DS.accent
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tint.opacity(0.18))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

// MARK: - Pill segmented control
struct SegmentPills: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    selection = i
                } label: {
                    Text(options[i])
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selection == i ? DS.inkPrimary : DS.inkTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selection == i ? DS.bgCardHi : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(DS.bgCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.hairline, lineWidth: 1))
    }
}
