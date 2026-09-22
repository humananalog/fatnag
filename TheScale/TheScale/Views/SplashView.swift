import SwiftUI

/// Cold open: full-bleed dark brand moment before home / onboarding.
/// Motion is intentional (scale rise, gold ring, haze drift), then soft exit.
struct SplashView: View {
    var onFinished: () -> Void

    @State private var ringScale: CGFloat = 0.72
    @State private var ringOpacity: Double = 0
    @State private var markOpacity: Double = 0
    @State private var markOffset: CGFloat = 18
    @State private var wordOpacity: Double = 0
    @State private var hazePhase: CGFloat = 0
    @State private var exitOpacity: Double = 1

    private let ink = Color(red: 0.04, green: 0.05, blue: 0.07)
    private let deep = Color(red: 0.07, green: 0.10, blue: 0.14)
    private let gold = Color(red: 0.82, green: 0.66, blue: 0.40)
    private let ivory = Color(red: 0.96, green: 0.95, blue: 0.92)
    private let mist = Color(red: 0.62, green: 0.64, blue: 0.68)

    var body: some View {
        ZStack {
            ink.ignoresSafeArea()

            // Atmospheric haze (same family as home weekly-goal haze).
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate + hazePhase
                let slow = t / 14.0
                ZStack {
                    LinearGradient(
                        colors: [deep, ink, Color(red: 0.05, green: 0.08, blue: 0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Ellipse()
                        .fill(gold.opacity(0.10))
                        .frame(width: 340, height: 280)
                        .blur(radius: 56)
                        .offset(x: -70 + CGFloat(sin(slow)) * 40, y: -160 + CGFloat(cos(slow * 0.7)) * 30)
                    Ellipse()
                        .fill(Color(red: 0.18, green: 0.42, blue: 0.48).opacity(0.14))
                        .frame(width: 380, height: 300)
                        .blur(radius: 64)
                        .offset(x: 90 + CGFloat(cos(slow * 0.55)) * 36, y: 120 + CGFloat(sin(slow * 0.9)) * 28)
                }
                .ignoresSafeArea()
            }

            VStack(spacing: 28) {
                ZStack {
                    // Outer gold ring
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [gold.opacity(0.15), gold, gold.opacity(0.35), gold.opacity(0.15)],
                                center: .center
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 168, height: 168)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    // Inner disc (scale plate)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.14, green: 0.16, blue: 0.20),
                                    Color(red: 0.06, green: 0.07, blue: 0.09)
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 80
                            )
                        )
                        .frame(width: 128, height: 128)
                        .overlay(
                            Circle()
                                .strokeBorder(ivory.opacity(0.12), lineWidth: 1)
                        )
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    // Needle / brand mark
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .opacity(markOpacity)
                        .offset(y: markOffset)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 8) {
                    Text("The Scale")
                        .font(.system(size: 36, weight: .semibold, design: .serif))
                        .foregroundStyle(ivory)
                        .tracking(0.6)
                    Text("Weigh. Steady. Advance.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(mist)
                        .tracking(1.1)
                }
                .opacity(wordOpacity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("splash.brand")
            }
        }
        .opacity(exitOpacity)
        .preferredColorScheme(.dark)
        .accessibilityAddTraits(.isHeader)
        .onAppear { runSequence() }
    }

    private func runSequence() {
        withAnimation(.easeOut(duration: 0.55)) {
            ringOpacity = 1
            ringScale = 1
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.12)) {
            markOpacity = 1
            markOffset = 0
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.28)) {
            wordOpacity = 1
        }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            hazePhase = 1
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_650_000_000)
            withAnimation(.easeInOut(duration: 0.42)) {
                exitOpacity = 0
                ringScale = 1.08
            }
            try? await Task.sleep(nanoseconds: 420_000_000)
            onFinished()
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
