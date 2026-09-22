import SwiftUI
import UIKit

/// Stylized analog scale: ticks + hand. User selects dream weight by rotating.
struct AnalogDreamScaleView: View {
    @Binding var weightKg: Double
    var boundsKg: ClosedRange<Double>
    var unitSystem: PreferredUnitSystem
    var ink: Color
    var steel: Color
    var accent: Color

    @State private var lastMinorTick: Int = .min
    @State private var lastMajorTick: Int = .min

    private let minorStepKg: Double = 0.5
    private let majorEvery: Int = 5 // every 5 minor ticks = 2.5 kg

    private var displayValue: Double {
        UnitFormat.mass(fromKg: weightKg, system: unitSystem)
    }

    private var fraction: Double {
        let span = boundsKg.upperBound - boundsKg.lowerBound
        guard span > 0.01 else { return 0.5 }
        return min(max((weightKg - boundsKg.lowerBound) / span, 0), 1)
    }

    /// Hand angle: -120° … +120°.
    private var handDegrees: Double {
        -120 + fraction * 240
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color(red: 0.88, green: 0.90, blue: 0.93)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 140
                        )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(ink.opacity(0.18), lineWidth: 2)
                    )

                ticksLayer

                Capsule()
                    .fill(accent)
                    .frame(width: 4, height: 78)
                    .offset(y: -40)
                    .rotationEffect(.degrees(handDegrees))
                    .shadow(color: ink.opacity(0.25), radius: 2, y: 1)

                Circle()
                    .fill(ink)
                    .frame(width: 14, height: 14)

                VStack(spacing: 2) {
                    Text(String(format: "%.1f", displayValue))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .monospacedDigit()
                    Text(unitSystem.massLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(steel)
                }
                .offset(y: 52)
            }
            .frame(width: 240, height: 240)
            .contentShape(Circle())
            .gesture(dragGesture)
            .accessibilityIdentifier("onboarding.dream.analog")
            .accessibilityLabel("Dream weight \(String(format: "%.1f", displayValue)) \(unitSystem.massLabel)")
            .accessibilityValue(String(format: "%.1f %@", displayValue, unitSystem.massLabel))
            .accessibilityAdjustableAction { direction in
                let step = unitSystem == .metric ? 0.5 : UnitFormat.kg(fromMass: 1, system: .imperial)
                switch direction {
                case .increment:
                    setKg(weightKg + step)
                case .decrement:
                    setKg(weightKg - step)
                @unknown default:
                    break
                }
            }

            Text("Drag the dial. Haptics on ticks.")
                .font(.caption)
                .foregroundStyle(steel)
        }
    }

    private var ticksLayer: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2 - 8
            let span = boundsKg.upperBound - boundsKg.lowerBound
            let tickCount = max(Int((span / minorStepKg).rounded()), 1)
            for i in 0...tickCount {
                let t = Double(i) / Double(tickCount)
                let deg = -120 + t * 240
                let rad = deg * .pi / 180
                let isMajor = i % majorEvery == 0
                let inner = outer - (isMajor ? 16 : 9)
                let cosA = Darwin.cos(rad)
                let sinA = Darwin.sin(rad)
                var path = Path()
                path.move(to: CGPoint(x: center.x + cosA * inner, y: center.y + sinA * inner))
                path.addLine(to: CGPoint(x: center.x + cosA * outer, y: center.y + sinA * outer))
                context.stroke(
                    path,
                    with: .color(isMajor ? ink.opacity(0.55) : steel.opacity(0.35)),
                    lineWidth: isMajor ? 2 : 1
                )
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let center = CGPoint(x: 120, y: 120)
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                var deg = atan2(dy, dx) * 180 / .pi
                // Map -180…180 into dial -120…120, clamp outside.
                if deg < -120 { deg = -120 }
                if deg > 120 { deg = 120 }
                let t = (deg + 120) / 240
                let raw = boundsKg.lowerBound + t * (boundsKg.upperBound - boundsKg.lowerBound)
                let snapped = (raw / minorStepKg).rounded() * minorStepKg
                setKg(snapped)
            }
    }

    private func setKg(_ kg: Double) {
        let clamped = min(max(kg, boundsKg.lowerBound), boundsKg.upperBound)
        let snapped = (clamped / minorStepKg).rounded() * minorStepKg
        let minorIndex = Int((snapped / minorStepKg).rounded())
        if minorIndex != lastMinorTick {
            lastMinorTick = minorIndex
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
            if minorIndex % majorEvery == 0, minorIndex != lastMajorTick {
                lastMajorTick = minorIndex
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
            }
        }
        weightKg = snapped
    }
}
