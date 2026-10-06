import SwiftUI

/// Cold open: Netflix-style wordmark slam on pure black, then soft handoff to the app.
/// Uses the fatnag SVG asset plus animatable thin/heavy letter groups.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var markScale: CGFloat = 6.2
    @State private var markOpacity: Double = 0
    @State private var fatOpacity: Double = 0
    @State private var nagOpacity: Double = 0
    @State private var nagScale: CGFloat = 1.35
    @State private var bloomOpacity: Double = 0
    @State private var tagOpacity: Double = 0
    @State private var exitOpacity: Double = 1
    @State private var impactTick = false
    /// Frozen at appear from last Settings language, or system on first launch.
    @State private var tagline = AppLanguageStore.splashTagline

    private let ink = Color.black
    private let ivory = Color.white

    var body: some View {
        ZStack {
            ink.ignoresSafeArea()

            // Impact bloom (Netflix slam flash), skipped when Reduce Transparency is on.
            if !reduceTransparency {
                RadialGradient(
                    colors: [
                        ivory.opacity(bloomOpacity * 0.22),
                        ivory.opacity(bloomOpacity * 0.06),
                        .clear
                    ],
                    center: .center,
                    startRadius: 8,
                    endRadius: 280
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(spacing: 22) {
                // SVG vector (template) sits under the animatable type for accessibility /
                // asset parity; animatable HStack drives the Netflix weight reveal.
                ZStack {
                    FatnagBrand.wordmarkImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: 260, height: 58)
                        .opacity(0.001)
                        .accessibilityHidden(true)

                    HStack(spacing: 0) {
                        Text(verbatim: "fat")
                            .font(.system(size: 52, weight: .light, design: .default))
                            .opacity(fatOpacity)
                        Text(verbatim: "nag")
                            .font(.system(size: 52, weight: .heavy, design: .default))
                            .opacity(nagOpacity)
                            .scaleEffect(nagScale)
                    }
                    .foregroundStyle(ivory)
                    .tracking(-1.4)
                }
                .scaleEffect(markScale)
                .opacity(markOpacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("fatnag")
                .accessibilityIdentifier("splash.brand")

                Text(tagline)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(ivory.opacity(0.78))
                    .tracking(0.2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .lineLimit(2)
                    .opacity(tagOpacity)
                    .accessibilityIdentifier("splash.tagline")
            }
            .padding(.horizontal, 28)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(splashVersionLine)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(ivory.opacity(0.36))
                        .monospacedDigit()
                        .opacity(tagOpacity)
                        .accessibilityIdentifier("splash.version")
                }
            }
            .safeAreaPadding(.trailing, 20)
            .safeAreaPadding(.bottom, 16)
        }
        .opacity(exitOpacity)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.85), trigger: impactTick)
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            tagline = AppLanguageStore.splashTagline
            runSequence()
        }
    }

    private var splashVersionLine: String {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(marketing)"
    }

    private func runSequence() {
        if reduceMotion {
            markScale = 1
            markOpacity = 1
            fatOpacity = 1
            nagOpacity = 1
            nagScale = 1
            tagOpacity = 1
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                withAnimation(.easeInOut(duration: 0.28)) { exitOpacity = 0 }
                try? await Task.sleep(nanoseconds: 280_000_000)
                onFinished()
            }
            return
        }

        // 1) Void beat — black frame (Netflix cold open).
        markScale = 6.2
        markOpacity = 0
        fatOpacity = 0
        nagOpacity = 0
        nagScale = 1.35

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)

            // 2) Slam: whole mark rushes in from oversized scale.
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                markScale = 1
                markOpacity = 1
                fatOpacity = 1
            }
            try? await Task.sleep(nanoseconds: 120_000_000)

            // Bold "nag" lands a beat later with a punch.
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                nagOpacity = 1
                nagScale = 1
            }
            withAnimation(.easeOut(duration: 0.18)) {
                bloomOpacity = 1
            }
            impactTick.toggle()

            try? await Task.sleep(nanoseconds: 160_000_000)
            withAnimation(.easeOut(duration: 0.55)) {
                bloomOpacity = 0
            }
            withAnimation(.easeOut(duration: 0.4)) {
                tagOpacity = 1
            }

            try? await Task.sleep(nanoseconds: 980_000_000)

            // 3) Exit: slight push-in + fade (hand off to landing / onboarding).
            withAnimation(.easeIn(duration: 0.48)) {
                markScale = 1.12
                exitOpacity = 0
                tagOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 480_000_000)
            onFinished()
        }
    }
}

#Preview("Splash") {
    SplashView(onFinished: {})
}

// MARK: - First launch landing (after splash)

/// First-launch landing after onboarding. Send-off into the first weigh.
/// Karaoke wipe on huge type, background dark to fired.
/// Three screens max. Auto-advances. Tap skips a line. Skip control after 0.7s.
/// Reduce Motion: final frame + Continue, no wipe.
struct FirstLaunchLandingView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var lineIndex = 0
    @State private var wipe: CGFloat = 0
    @State private var heat: CGFloat = 0
    @State private var lineScale: CGFloat = 1.16
    @State private var lineOpacity: Double = 0
    @State private var showSkip = false
    @State private var exiting = false
    @State private var impactTick = false
    @State private var playTask: Task<Void, Never>?

    private static let script: [LandingBeat] = [
        LandingBeat(text: "Done pretending it fixes itself.", pause: 0.55),
        LandingBeat(text: "Lie. Get offended. That's the point.", pause: 0.55),
        LandingBeat(text: "Go weigh yourself. Now.", pause: 1.05)
    ]

    var body: some View {
        ZStack {
            FiredBackground(heat: heat, reduceTransparency: reduceTransparency, reduceMotion: reduceMotion)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                FatnagWordmark(size: 22, color: Color.white.opacity(0.42))
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                Spacer(minLength: 12)

                if reduceMotion {
                    reducedCopy
                } else {
                    karaokeStage
                }

                Spacer(minLength: 12)

                HStack {
                    Text("Honest coach. Real numbers.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.38))
                    Spacer()
                    if showSkip || reduceMotion {
                        Button(reduceMotion ? "Continue" : "Skip") {
                            finish()
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .accessibilityIdentifier("landing.skip")
                    }
                }
            }
            .padding(.horizontal, ScaleLayout.pageInset)
            .safeAreaPadding(.top, 8)
            .safeAreaPadding(.bottom, 18)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .opacity(exiting ? 0 : 1)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.72), trigger: impactTick)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.script.map(\.text).joined(separator: " "))
        .accessibilityIdentifier("landing.root")
        .contentShape(Rectangle())
        .onTapGesture { advanceFromTap() }
        .onAppear { start() }
        .onDisappear { playTask?.cancel() }
    }

    private var karaokeStage: some View {
        let beat = Self.script[min(lineIndex, Self.script.count - 1)]
        return ZStack(alignment: .leading) {
            Text(beat.text)
                .font(landingFont)
                .foregroundStyle(Color.white.opacity(0.18))
                .fixedSize(horizontal: false, vertical: true)

            Text(beat.text)
                .font(landingFont)
                .foregroundStyle(karaokeInk)
                .fixedSize(horizontal: false, vertical: true)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: max(0, geo.size.width * wipe))
                    }
                }
        }
        .multilineTextAlignment(.leading)
        .minimumScaleFactor(0.62)
        .lineLimit(3)
        .scaleEffect(lineScale)
        .opacity(lineOpacity)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("landing.line")
    }

    private var reducedCopy: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(Self.script.enumerated()), id: \.offset) { _, beat in
                Text(beat.text)
                    .font(.system(size: 28, weight: .heavy, design: .default))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .minimumScaleFactor(0.7)
    }

    private var landingFont: Font {
        .system(size: 44, weight: .heavy, design: .default)
    }

    private var karaokeInk: Color {
        let hot = min(1, max(0, heat))
        return Color(
            red: 1.0,
            green: 0.42 + 0.46 * hot,
            blue: 0.16 + 0.22 * hot
        )
    }

    private func start() {
        if reduceMotion {
            heat = 0.85
            showSkip = true
            return
        }
        playTask?.cancel()
        playTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !Task.isCancelled { showSkip = true }
        }
        playLine(at: 0)
    }

    private func playLine(at index: Int) {
        guard !exiting else { return }
        guard index < Self.script.count else {
            finish()
            return
        }
        lineIndex = index
        wipe = 0
        lineScale = 1.18
        lineOpacity = 0
        impactTick.toggle()

        let targetHeat = CGFloat(index + 1) / CGFloat(Self.script.count)
        withAnimation(.easeInOut(duration: 0.55)) {
            heat = targetHeat
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            lineScale = 1
            lineOpacity = 1
        }

        let beat = Self.script[index]
        let wipeDuration = beat.wipeDuration
        playTask?.cancel()
        playTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: wipeDuration)) {
                wipe = 1
            }
            let pauseNs = UInt64((wipeDuration + beat.pause) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: pauseNs)
            guard !Task.isCancelled else { return }
            playLine(at: index + 1)
        }
    }

    private func advanceFromTap() {
        guard !reduceMotion, !exiting else { return }
        if lineIndex >= Self.script.count - 1, wipe >= 0.95 {
            finish()
            return
        }
        playLine(at: min(lineIndex + 1, Self.script.count - 1))
    }

    private func finish() {
        guard !exiting else { return }
        exiting = true
        playTask?.cancel()
        withAnimation(.easeIn(duration: 0.32)) {
            heat = 1
            lineOpacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 340_000_000)
            onFinished()
        }
    }
}

private struct LandingBeat {
    let text: String
    let pause: TimeInterval

    var wipeDuration: TimeInterval {
        let words = max(2, text.split(separator: " ").count)
        return min(2.1, 0.28 * Double(words))
    }
}

/// Dark void that cooks into ember as the script advances.
private struct FiredBackground: View {
    var heat: CGFloat
    var reduceTransparency: Bool
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 20.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let drift = t / 7.2
            let h = min(1, max(0, heat))

            let void = Color.black
            let coal = Color(red: 0.16 + 0.10 * h, green: 0.03, blue: 0.01)
            let ember = Color(red: 0.62 + 0.28 * h, green: 0.14 + 0.16 * h, blue: 0.03)
            let flame = Color(red: 1.0, green: 0.38 + 0.34 * h, blue: 0.08)

            ZStack {
                LinearGradient(
                    colors: [void, coal, ember.opacity(0.55 + 0.35 * h)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if !reduceTransparency {
                    Ellipse()
                        .fill(ember.opacity(0.34 + 0.28 * h))
                        .frame(width: 340, height: 260)
                        .blur(radius: 54)
                        .offset(
                            x: -40 + CGFloat(sin(drift) * 30),
                            y: 220 + CGFloat(cos(drift * 0.7) * 24)
                        )
                    Ellipse()
                        .fill(flame.opacity(0.18 + 0.32 * h))
                        .frame(width: 280, height: 220)
                        .blur(radius: 48)
                        .offset(
                            x: 70 + CGFloat(cos(drift * 0.8) * 36),
                            y: 260 + CGFloat(sin(drift * 0.6) * 20)
                        )
                    Ellipse()
                        .fill(Color.white.opacity(0.04 + 0.10 * h))
                        .frame(width: 160, height: 120)
                        .blur(radius: 28)
                        .offset(x: 10, y: 300)
                }
            }
        }
    }
}

#Preview("Landing") {
    FirstLaunchLandingView(onFinished: {})
}
