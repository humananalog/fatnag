import SwiftUI

/// Full-screen first-of-month hero. Gender palette, season atmosphere, one action.
/// Plus/Pro may replace the insight with Keel. Free stays on the rule line.
struct MonthlyHeroCardView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var playID = 0
    @State private var revealed = false
    @State private var drawGraph = false
    @State private var countStart = Date()

    private var universe: ScalePaletteUniverse {
        ScalePaletteUniverse.resolve(sex: session.profile.sex)
    }

    private var ink: Color { Color(red: 0.97, green: 0.95, blue: 0.92) }
    private var mist: Color {
        universe == .bloomCopper
            ? Color(red: 0.86, green: 0.74, blue: 0.70)
            : Color(red: 0.70, green: 0.78, blue: 0.82)
    }

    var body: some View {
        ZStack {
            atmosphere.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if let card = session.monthlyHero {
                    hero(card)
                } else {
                    ProgressView()
                        .tint(ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .preferredColorScheme(.dark)
        .onAppear { play() }
        .accessibilityIdentifier("monthlyHero")
    }

    private var topBar: some View {
        HStack {
            Button {
                session.dismissMonthlyHero()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ink.opacity(0.92))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(AppLanguageStore.text("monthly.close_a11y", default: "Close monthly card"))

            Spacer(minLength: 8)

            Button {
                play()
            } label: {
                Label(AppLanguageStore.text("monthly.replay", default: "Replay"), systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("monthlyHero.replay")
        }
        .padding(.bottom, 6)
    }

    private func hero(_ card: MonthlyHeroPayload) -> some View {
        let facts = card.facts
        let accent = accentColor(facts)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(facts.monthName.uppercased())  \(facts.festivalEmoji)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(accent)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 10)
                    .accessibilityIdentifier("monthlyHero.festival")

                Text(facts.festivalTitle)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(ink.opacity(0.78))
                    .padding(.top, 8)
                    .opacity(revealed ? 1 : 0)

                Text(facts.bigWord)
                    .font(.system(size: facts.visual == .graph ? 42 : 64, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, 18)
                    .scaleEffect(revealed ? 1 : 0.86)
                    .opacity(revealed ? 1 : 0)
                    .accessibilityIdentifier("monthlyHero.word")

                heroNumber(facts, accent: accent)
                    .padding(.top, 4)

                if let unit = facts.unit {
                    unitRow(unit)
                        .padding(.top, 10)
                }

                emojiBurst(facts)
                    .padding(.top, 16)

                if facts.visual == .graph, facts.sparkline.count >= 2 {
                    sparkline(facts, accent: accent)
                        .padding(.top, 18)
                        .accessibilityIdentifier("monthlyHero.graph")
                }

                Text(displayInsight(card))
                    .font(.system(size: facts.visual == .bigType ? 26 : 22, weight: .bold, design: .serif))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 12)
                    .accessibilityIdentifier("monthlyHero.insight")

                if session.isMonthlyHeroLoading, facts.canAskKeel, MonthlyHeroEngine.allowsLiveInsight(plan: ScaleSubscriptionStore.shared.plan) {
                    Text(AppLanguageStore.text("monthly.keel_thinking", default: "Keel is sharpening the line…"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(mist)
                        .padding(.top, 8)
                }

                actionBlock(facts, accent: accent)
                    .padding(.top, 22)

                Text(sourceLabel(card))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(mist.opacity(0.85))
                    .padding(.top, 14)
                    .accessibilityIdentifier("monthlyHero.source")

                Button {
                    session.dismissMonthlyHero()
                } label: {
                    Text(AppLanguageStore.text("monthly.lock", default: "On it"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(universe == .bloomCopper
                            ? Color(red: 0.16, green: 0.08, blue: 0.08)
                            : Color(red: 0.05, green: 0.08, blue: 0.10))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
                .opacity(revealed ? 1 : 0)
                .accessibilityIdentifier("monthlyHero.cta")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
    }

    private func heroNumber(_ facts: MonthlyHeroFacts, accent: Color) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let progress = countProgress(at: context.date)
            let parts = formattedNumber(facts, progress: progress)
            return HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(parts.number)
                    .font(.system(size: facts.visual == .graph ? 64 : 76, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(parts.suffix)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(mist)
                Spacer(minLength: 0)
            }
            .opacity(revealed ? 1 : 0)
            .accessibilityIdentifier("monthlyHero.delta")
        }
    }

    private func unitRow(_ unit: MonthlyRelatableUnit) -> some View {
        HStack(spacing: 8) {
            Text(String(repeating: unit.emoji, count: min(unit.burstCount, 6)))
                .font(.system(size: 22))
                .scaleEffect(revealed ? 1 : 0.4)
                .opacity(revealed ? 1 : 0)
            Text(unit.phrase)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ink.opacity(0.9))
        }
        .accessibilityIdentifier("monthlyHero.unit")
    }

    private func emojiBurst(_ facts: MonthlyHeroFacts) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(facts.burst.prefix(5).enumerated()), id: \.offset) { index, emoji in
                Text(emoji)
                    .font(.system(size: facts.visual == .bigType ? 36 : 28))
                    .scaleEffect(revealed ? 1 : 0.2)
                    .opacity(revealed ? 1 : 0)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.62).delay(0.12 + Double(index) * 0.07),
                        value: revealed
                    )
            }
        }
        .accessibilityIdentifier("monthlyHero.emojis")
    }

    private func sparkline(_ facts: MonthlyHeroFacts, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonthlySparkline(values: facts.sparkline)
                .trim(from: 0, to: drawGraph ? 1 : 0)
                .stroke(accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .frame(height: 120)
                .background(alignment: .bottom) {
                    Capsule()
                        .fill(accent.opacity(0.18))
                        .frame(height: 2)
                }
            Text(graphCaption(facts))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(mist)
        }
        .animation(.easeInOut(duration: 1.25), value: drawGraph)
    }

    private func actionBlock(_ facts: MonthlyHeroFacts, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(facts.monthlyAction)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.45), lineWidth: 1)
                )
                .accessibilityIdentifier("monthlyHero.action")

            if let note = facts.medicalNote {
                Text(note)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.98, green: 0.82, blue: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("monthlyHero.medical")
            }
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 16)
    }

    private var atmosphere: some View {
        let month = session.monthlyHero?.facts.month ?? Calendar.current.component(.month, from: Date())
        let wash = seasonWash(month: month)
        return TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let slow = t / 14.0
            ZStack {
                LinearGradient(
                    colors: [wash.voidTop, wash.voidMid, wash.voidBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle()
                    .fill(wash.primary.opacity(0.55))
                    .frame(width: 320, height: 320)
                    .blur(radius: 50)
                    .offset(x: -80 + CGFloat(sin(slow)) * 28, y: -180 + CGFloat(cos(slow * 0.8)) * 20)
                Circle()
                    .fill(wash.secondary.opacity(0.42))
                    .frame(width: 280, height: 280)
                    .blur(radius: 60)
                    .offset(x: 110 + CGFloat(cos(slow * 0.6)) * 24, y: 160)
                if month == 12 || month == 1 {
                    ForEach(0..<8, id: \.self) { index in
                        Circle()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 3, height: 3)
                            .offset(
                                x: CGFloat(index * 46 - 160) + CGFloat(sin(slow + Double(index))) * 8,
                                y: CGFloat((index * 90) % 520) - 200 + CGFloat(cos(slow * 1.4 + Double(index))) * 30
                            )
                    }
                }
            }
        }
    }

    private func play() {
        revealed = false
        drawGraph = false
        playID += 1
        countStart = Date()
        withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
            revealed = true
        }
        withAnimation(.easeInOut(duration: 1.25).delay(0.25)) {
            drawGraph = true
        }
    }

    private func countProgress(at date: Date) -> Double {
        _ = playID
        let raw = min(1, max(0, date.timeIntervalSince(countStart) / 1.05))
        return 1 - pow(1 - raw, 3)
    }

    private func formattedNumber(_ facts: MonthlyHeroFacts, progress: Double) -> (number: String, suffix: String) {
        guard let kg = facts.heroNumberKg else { return ("—", "") }
        let shown = kg * progress
        let system = session.preferredUnits
        if facts.heroNumberIsDelta {
            if facts.direction == .stable {
                if abs(kg) < 1, system == .metric {
                    return ("±\(Int((abs(shown) * 1000).rounded()))", "g")
                }
                let value = UnitFormat.mass(fromKg: abs(shown), system: system)
                return ("±\(String(format: "%.1f", value))", system.massLabel)
            }
            let sign = facts.direction == .gain ? "+" : "−"
            if abs(kg) < 1, system == .metric {
                return ("\(sign)\(Int((abs(shown) * 1000).rounded()))", "g")
            }
            let value = UnitFormat.mass(fromKg: abs(shown), system: system)
            return ("\(sign)\(String(format: "%.1f", value))", system.massLabel)
        }
        let value = UnitFormat.mass(fromKg: shown, system: system)
        return (String(format: "%.1f", value), system.massLabel)
    }

    private func displayInsight(_ card: MonthlyHeroPayload) -> String {
        let live = session.monthlyHeroStreamInsight.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { return live }
        if !card.insight.isEmpty { return card.insight }
        return card.facts.ruleInsight
    }

    private func sourceLabel(_ card: MonthlyHeroPayload) -> String {
        if card.usedNetwork {
            return AppLanguageStore.text("monthly.source.keel", default: "KEEL")
        }
        return AppLanguageStore.text("monthly.source.rules", default: "HOUSE RULES")
    }

    private func graphCaption(_ facts: MonthlyHeroFacts) -> String {
        switch facts.direction {
        case .loss: return facts.sinceLine.isEmpty ? "The line fell." : "The line fell \(facts.sinceLine)."
        case .gain: return facts.sinceLine.isEmpty ? "The line rose." : "The line rose \(facts.sinceLine)."
        case .stable: return "Flat. That's a result."
        case .unknown: return ""
        }
    }

    private func accentColor(_ facts: MonthlyHeroFacts) -> Color {
        switch universe {
        case .glacierForge:
            switch facts.direction {
            case .loss: return Color(red: 0.45, green: 0.93, blue: 0.84)
            case .gain: return Color(red: 0.98, green: 0.62, blue: 0.42)
            case .stable, .unknown: return Color(red: 0.72, green: 0.84, blue: 0.96)
            }
        case .bloomCopper:
            switch facts.direction {
            case .loss: return Color(red: 0.98, green: 0.78, blue: 0.55)
            case .gain: return Color(red: 0.96, green: 0.48, blue: 0.52)
            case .stable, .unknown: return Color(red: 0.98, green: 0.82, blue: 0.74)
            }
        }
    }

    private func seasonWash(month: Int) -> (voidTop: Color, voidMid: Color, voidBottom: Color, primary: Color, secondary: Color) {
        switch universe {
        case .glacierForge:
            switch month {
            case 12, 1, 2:
                return (
                    Color(red: 0.05, green: 0.08, blue: 0.14),
                    Color(red: 0.07, green: 0.12, blue: 0.18),
                    Color(red: 0.04, green: 0.06, blue: 0.10),
                    Color(red: 0.45, green: 0.78, blue: 0.95),
                    Color(red: 0.70, green: 0.82, blue: 0.95)
                )
            case 6, 7, 8:
                return (
                    Color(red: 0.04, green: 0.10, blue: 0.12),
                    Color(red: 0.06, green: 0.16, blue: 0.16),
                    Color(red: 0.03, green: 0.07, blue: 0.09),
                    Color(red: 0.20, green: 0.82, blue: 0.72),
                    Color(red: 0.95, green: 0.78, blue: 0.28)
                )
            case 9, 10, 11:
                return (
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.10, green: 0.10, blue: 0.12),
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.95, green: 0.55, blue: 0.22),
                    Color(red: 0.25, green: 0.62, blue: 0.70)
                )
            default:
                return (
                    Color(red: 0.05, green: 0.10, blue: 0.12),
                    Color(red: 0.07, green: 0.14, blue: 0.14),
                    Color(red: 0.04, green: 0.07, blue: 0.09),
                    Color(red: 0.35, green: 0.82, blue: 0.62),
                    Color(red: 0.45, green: 0.75, blue: 0.90)
                )
            }
        case .bloomCopper:
            switch month {
            case 12, 1, 2:
                return (
                    Color(red: 0.12, green: 0.07, blue: 0.10),
                    Color(red: 0.16, green: 0.08, blue: 0.12),
                    Color(red: 0.08, green: 0.04, blue: 0.07),
                    Color(red: 0.95, green: 0.72, blue: 0.78),
                    Color(red: 0.78, green: 0.84, blue: 0.95)
                )
            case 6, 7, 8:
                return (
                    Color(red: 0.14, green: 0.06, blue: 0.07),
                    Color(red: 0.18, green: 0.08, blue: 0.08),
                    Color(red: 0.08, green: 0.04, blue: 0.05),
                    Color(red: 0.98, green: 0.55, blue: 0.38),
                    Color(red: 0.98, green: 0.78, blue: 0.42)
                )
            case 9, 10, 11:
                return (
                    Color(red: 0.12, green: 0.06, blue: 0.07),
                    Color(red: 0.16, green: 0.07, blue: 0.08),
                    Color(red: 0.07, green: 0.04, blue: 0.05),
                    Color(red: 0.92, green: 0.48, blue: 0.32),
                    Color(red: 0.82, green: 0.55, blue: 0.38)
                )
            default:
                return (
                    Color(red: 0.12, green: 0.07, blue: 0.09),
                    Color(red: 0.16, green: 0.08, blue: 0.11),
                    Color(red: 0.08, green: 0.04, blue: 0.07),
                    Color(red: 0.96, green: 0.62, blue: 0.70),
                    Color(red: 0.92, green: 0.74, blue: 0.48)
                )
            }
        }
    }
}

/// Weight line, lower mass toward the bottom so a loss visibly drops.
private struct MonthlySparkline: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count >= 2 else { return Path() }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 0.2)
        let pad = span * 0.18
        let low = minV - pad
        let high = maxV + pad
        func point(_ index: Int) -> CGPoint {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1)
            let t = (values[index] - low) / (high - low)
            let y = rect.maxY - rect.height * CGFloat(t)
            return CGPoint(x: x, y: y)
        }
        var path = Path()
        path.move(to: point(0))
        for index in 1..<values.count {
            path.addLine(to: point(index))
        }
        return path
    }
}

#Preview {
    MonthlyHeroCardView()
        .environmentObject(ScaleSessionViewModel())
}
