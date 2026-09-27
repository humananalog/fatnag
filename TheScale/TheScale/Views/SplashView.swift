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

            VStack(spacing: 20) {
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
                        Text("fat")
                            .font(.system(size: 52, weight: .light, design: .default))
                            .opacity(fatOpacity)
                        Text("nag")
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

                VStack(spacing: 6) {
                    Text(FatnagBrand.tagline)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(ivory.opacity(0.55))
                        .tracking(0.3)
                        .multilineTextAlignment(.center)
                    Text(splashVersionLine)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(ivory.opacity(0.38))
                        .monospacedDigit()
                        .accessibilityIdentifier("splash.version")
                }
                .opacity(tagOpacity)
            }
            .padding(.horizontal, 28)
        }
        .opacity(exitOpacity)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.85), trigger: impactTick)
        .accessibilityAddTraits(.isHeader)
        .onAppear { runSequence() }
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

            // 3) Exit: slight push-in + fade (hand off to home / onboarding).
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

#Preview {
    SplashView(onFinished: {})
}
