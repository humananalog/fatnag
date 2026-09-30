import SwiftUI

/// Spotify-style first-of-month story. Two viewport pages, auto-scrolled.
/// Page 1: DOWN with the delta on its right, then a hard emoji zoom.
/// Page 2: the line with start and end weights, then a big insight streamed word by word.
struct MonthlyHeroCardView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var playID = 0
    @State private var revealed = false
    @State private var drawGraph = false
    @State private var countStart = Date()
    @State private var emojiPhase = 0
    @State private var shownWords = 0

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
        GeometryReader { geo in
            let page = geo.size.height
            ZStack(alignment: .top) {
                atmosphere.ignoresSafeArea()
                if let card = session.monthlyHero {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                firstPage(card, height: page)
                                    .id("monthlyHero.page1")
                                secondPage(card, height: page)
                                    .id("monthlyHero.page2")
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .task(id: playID) {
                            await runStory(proxy)
                        }
                    }
                } else {
                    ProgressView()
                        .tint(ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                topBar
            }
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
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func firstPage(_ card: MonthlyHeroPayload, height: CGFloat) -> some View {
        let facts = card.facts
        let accent = accentColor(facts)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(facts.monthName.uppercased())  \(facts.festivalEmoji)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(2.6)
                .foregroundStyle(accent)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 16)
                .accessibilityIdentifier("monthlyHero.festival")

            Text(facts.festivalTitle)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(ink.opacity(0.78))
                .padding(.top, 8)
                .opacity(revealed ? 1 : 0)

            headlineRow(facts, accent: accent)
                .padding(.top, 28)

            Spacer(minLength: 12)

            emojiStage(facts, accent: accent)

            if let unit = facts.unit {
                Text(unit.phrase)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .padding(.top, 18)
                    .scaleEffect(emojiPhase > 0 ? 1 : 0.6)
                    .opacity(emojiPhase > 0 ? 1 : 0)
                    .accessibilityIdentifier("monthlyHero.unit")
            }

            Spacer(minLength: 28)
        }
        .padding(.horizontal, 24)
        .padding(.top, 64)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
    }

    private func headlineRow(_ facts: MonthlyHeroFacts, accent: Color) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let parts = formattedNumber(facts, progress: countProgress(at: context.date))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(facts.bigWord)
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .accessibilityIdentifier("monthlyHero.word")
                Text(gluedDelta(parts))
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .scaleEffect(emojiPhase == 1 ? 1.08 : 1)
                    .accessibilityIdentifier("monthlyHero.delta")
            }
            .opacity(revealed ? 1 : 0)
            .offset(x: revealed ? 0 : -28)
        }
    }

    private func emojiStage(_ facts: MonthlyHeroFacts, accent: Color) -> some View {
        let hero = facts.unit?.emoji ?? facts.burst.first ?? facts.festivalEmoji
        let extras = Array(facts.burst.prefix(4))
        return ZStack {
            Circle()
                .fill(accent.opacity(emojiPhase == 1 ? 0.45 : 0.12))
                .frame(width: emojiPhase == 1 ? 300 : 80, height: emojiPhase == 1 ? 300 : 80)
                .blur(radius: emojiPhase == 1 ? 18 : 30)
                .animation(.spring(response: 0.38, dampingFraction: 0.45), value: emojiPhase)
            Text(hero)
                .font(.system(size: 120))
                .scaleEffect(emojiScale)
                .rotationEffect(.degrees(emojiPhase == 0 ? -22 : (emojiPhase == 1 ? 8 : 0)))
                .animation(.spring(response: 0.42, dampingFraction: 0.42), value: emojiPhase)
                .accessibilityIdentifier("monthlyHero.emojis")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .overlay(alignment: .bottom) {
            HStack(spacing: 14) {
                ForEach(Array(extras.enumerated()), id: \.offset) { index, emoji in
                    Text(emoji)
                        .font(.system(size: 36))
                        .scaleEffect(emojiPhase > 0 ? 1 : 0.05)
                        .opacity(emojiPhase > 0 ? 1 : 0)
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.5).delay(0.08 + Double(index) * 0.06),
                            value: emojiPhase
                        )
                }
            }
            .offset(y: 28)
        }
    }

    private var emojiScale: CGFloat {
        switch emojiPhase {
        case 1: return 1.62
        case 2: return 1
        default: return 0.06
        }
    }

    private func secondPage(_ card: MonthlyHeroPayload, height: CGFloat) -> some View {
        let facts = card.facts
        let accent = accentColor(facts)
        let words = insightWords(card)
        return VStack(alignment: .leading, spacing: 0) {
            if facts.sparkline.count >= 2 {
                sparkline(facts, accent: accent)
                    .padding(.top, 8)
            }

            MonthlyWordFlow(spacing: 8, lineSpacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    Text(word)
                        .font(.system(size: 36, weight: .heavy, design: .serif))
                        .foregroundStyle(index + 1 == shownWords ? accent : ink)
                        .opacity(index < shownWords ? 1 : 0)
                        .scaleEffect(index + 1 == shownWords ? 1.14 : (index < shownWords ? 1 : 0.72))
                        .animation(.spring(response: 0.28, dampingFraction: 0.62), value: shownWords)
                        .id("monthlyHero.word.\(index)")
                }
            }
            .padding(.top, 28)
            .accessibilityIdentifier("monthlyHero.insight")

            if session.isMonthlyHeroLoading, facts.canAskKeel, MonthlyHeroEngine.allowsLiveInsight(plan: ScaleSubscriptionStore.shared.plan) {
                Text(AppLanguageStore.text("monthly.keel_thinking", default: "Keel is sharpening the line…"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(mist)
                    .padding(.top, 10)
            }

            Spacer(minLength: 24)

            actionBlock(facts, accent: accent)
                .opacity(shownWords > 0 ? 1 : 0)

            Text(sourceLabel(card))
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(mist.opacity(0.85))
                .padding(.top, 16)
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
            .padding(.top, 18)
            .opacity(shownWords > 0 ? 1 : 0)
            .accessibilityIdentifier("monthlyHero.cta")
        }
        .padding(.horizontal, 24)
        .padding(.top, 72)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
    }

    private func sparkline(_ facts: MonthlyHeroFacts, accent: Color) -> some View {
        let start = facts.sparkline.first.map { endpointMass($0) } ?? ""
        let end = facts.sparkline.last.map { endpointMass($0) } ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(start)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(mist)
                    .accessibilityIdentifier("monthlyHero.graphStart")
                Spacer(minLength: 8)
                Text(end)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .accessibilityIdentifier("monthlyHero.graphEnd")
            }
            .opacity(drawGraph ? 1 : 0)

            MonthlySparkline(values: facts.sparkline)
                .trim(from: 0, to: drawGraph ? 1 : 0)
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(height: 150)
                .background(alignment: .bottom) {
                    Capsule()
                        .fill(accent.opacity(0.22))
                        .frame(height: 2)
                }
                .animation(.easeInOut(duration: 1.15), value: drawGraph)

            Text(graphCaption(facts))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(mist)
                .opacity(drawGraph ? 1 : 0)
        }
        .accessibilityIdentifier("monthlyHero.graph")
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
    }

    private func runStory(_ proxy: ScrollViewProxy) async {
        var jump = Transaction()
        jump.disablesAnimations = true
        withTransaction(jump) {
            proxy.scrollTo("monthlyHero.page1", anchor: .top)
        }
        guard await beat(0.12) else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            revealed = true
        }
        // Hold the headline so the count can land beside DOWN.
        guard await beat(1.15) else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.42)) {
            emojiPhase = 1
        }
        guard await beat(0.55) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
            emojiPhase = 2
        }
        // Pause on the zoomed emoji before the scroll.
        guard await beat(0.85) else { return }
        withAnimation(.easeInOut(duration: 1.35)) {
            proxy.scrollTo("monthlyHero.page2", anchor: .top)
        }
        guard await beat(0.55) else { return }
        withAnimation(.easeInOut(duration: 1.15)) {
            drawGraph = true
        }
        guard await beat(0.45) else { return }
        let words = insightWords(session.monthlyHero)
        for index in words.indices {
            shownWords = index + 1
            let token = words[index]
            let sentence = token.contains(".") || token.contains("!") || token.contains("?")
            if sentence {
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo("monthlyHero.word.\(index)", anchor: .center)
                }
            }
            guard await beat(sentence ? 0.42 : 0.09) else { return }
        }
        guard await beat(0.35) else { return }
        withAnimation(.easeInOut(duration: 0.8)) {
            proxy.scrollTo("monthlyHero.cta", anchor: .bottom)
        }
    }

    private func play() {
        revealed = false
        drawGraph = false
        emojiPhase = 0
        shownWords = 0
        countStart = Date()
        playID += 1
    }

    private func beat(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func insightWords(_ card: MonthlyHeroPayload?) -> [String] {
        guard let card else { return [] }
        let raw = displayInsight(card)
        return raw.split(whereSeparator: \.isWhitespace).map(String.init)
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

    /// Grams and ounces sit tight (`−400g`). Kilograms and pounds keep a space.
    private func gluedDelta(_ parts: (number: String, suffix: String)) -> String {
        if parts.suffix == "g" || parts.suffix == "oz" {
            return parts.number + parts.suffix
        }
        if parts.suffix.isEmpty { return parts.number }
        return parts.number + " " + parts.suffix
    }

    private func endpointMass(_ kg: Double) -> String {
        UnitFormat.massString(kg, system: session.preferredUnits, fractionDigits: 1)
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
                    .frame(width: 340, height: 340)
                    .blur(radius: 48)
                    .offset(x: -80 + CGFloat(sin(slow)) * 28, y: -200 + CGFloat(cos(slow * 0.8)) * 20)
                Circle()
                    .fill(wash.secondary.opacity(0.4))
                    .frame(width: 280, height: 280)
                    .blur(radius: 56)
                    .offset(x: 120 + CGFloat(cos(slow * 0.6)) * 24, y: 220)
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

/// Wrapping row of insight words. Unrevealed words keep their slot so the page does not jump.
private struct MonthlyWordFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = rows(subviews, maxWidth: width)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        var index = 0
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.height)),
                    proposal: ProposedViewSize(width: item.width, height: item.height)
                )
                x += item.width + spacing
                index += 1
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [CGSize]
        var height: CGFloat
    }

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var result: [Row] = []
        var current: [CGSize] = []
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if !current.isEmpty, x + size.width > maxWidth {
                result.append(Row(items: current, height: rowHeight))
                current = []
                x = 0
                rowHeight = 0
            }
            current.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        if !current.isEmpty {
            result.append(Row(items: current, height: rowHeight))
        }
        return result
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
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
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
