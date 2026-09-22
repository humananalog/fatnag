import SwiftUI

/// Home gauge composition: **Horizon Arc Bank**.
/// Large weekly % hero (matches the haze / serif home), then four BrandMark-style
/// luminous open arcs for steps / energy / protein / micro. No reticule, no HUD.
struct HorizonArcBankView: View {
    var weeklyPercent: Int
    var bandLabel: String
    var weekTitle: String
    var metrics: [DailyMetricProgress]
    var ink: Color
    var steel: Color
    var accent: Color
    var compact: Bool

    private let kinds: [DailyMetricProgress.Kind] = [.steps, .energy, .protein, .micro]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 18) {
            weeklyHero
            arcBank
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("home.horizonArcBank")
    }

    private var weeklyHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(weeklyPercent)")
                    .font(.system(size: compact ? 64 : 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .shadow(color: .white.opacity(0.55), radius: 0, y: 1)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityIdentifier("home.weekPercent")

                VStack(alignment: .leading, spacing: 4) {
                    Text(bandLabel.uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(ink)
                    Text("% of week")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(steel)
                }
                Spacer(minLength: 0)
            }

            Text(weekTitle)
                .font(.system(size: compact ? 15 : 17, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week goal \(weeklyPercent) percent, \(bandLabel). \(weekTitle)")
        .accessibilityIdentifier("home.weekHero")
    }

    private var arcBank: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ],
            spacing: compact ? 14 : 16
        ) {
            ForEach(kinds, id: \.rawValue) { kind in
                arcCell(for: kind)
            }
        }
        .accessibilityIdentifier("home.todayMetrics")
    }

    @ViewBuilder
    private func arcCell(for kind: DailyMetricProgress.Kind) -> some View {
        let row = metrics.first(where: { $0.kind == kind })
        let fraction = min(max(row?.fraction ?? 0, 0), 1.15)
        let color = statusColor(row?.status ?? .unknown)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(shortTitle(kind))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(ink.opacity(0.72))
                Spacer(minLength: 4)
                Text(statusChip(row))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            // BrandMark-style luminous open arc (not a closed Activity ring)
            ZStack {
                HorizonArcTrack()
                    .stroke(ink.opacity(0.14), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                HorizonArcTrack()
                    .trim(from: 0, to: min(CGFloat(fraction), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            }
            .frame(height: compact ? 36 : 42)
            .frame(maxWidth: .infinity)

            Text(valueLine(row))
                .font(.system(size: compact ? 17 : 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .shadow(color: .white.opacity(0.35), radius: 0, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row?.accessibilitySummary ?? "\(kind.rawValue) unavailable")
        .accessibilityIdentifier("home.todayMetrics.\(kind.rawValue)")
    }

    private func shortTitle(_ kind: DailyMetricProgress.Kind) -> String {
        switch kind {
        case .steps: return "STEPS"
        case .energy: return "ENERGY"
        case .protein: return "PROTEIN"
        case .micro: return "MICRO"
        }
    }

    private func statusChip(_ row: DailyMetricProgress?) -> String {
        guard let row else { return "-" }
        switch row.status {
        case .complete: return "Done"
        case .over: return "Over"
        case .unknown: return "Open"
        case .inProgress:
            return "\(Int((min(row.fraction, 1) * 100).rounded()))%"
        }
    }

    private func valueLine(_ row: DailyMetricProgress?) -> String {
        guard let row else { return "-" }
        return row.currentLine
    }

    private func statusColor(_ status: DailyMetricProgress.Status) -> Color {
        switch status {
        case .complete: return Color(red: 0.12, green: 0.42, blue: 0.30)
        case .over: return Color(red: 0.72, green: 0.22, blue: 0.18)
        case .inProgress: return accent
        case .unknown: return ink.opacity(0.28)
        }
    }
}

/// Single BrandMark-inspired arc segment (open, luminous track geometry).
private struct HorizonArcTrack: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 4
        let start = CGPoint(x: rect.minX + inset, y: rect.maxY - inset)
        let end = CGPoint(x: rect.maxX - inset, y: rect.minY + inset * 0.4)
        let control = CGPoint(x: rect.midX * 0.55, y: rect.minY - rect.height * 0.15)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}
