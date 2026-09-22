import SwiftUI
import UIKit

/// Real bathroom-scale UX: fixed center marker, marks live on a rotating disc.
/// Viewport shows roughly 25° of the disc (narrow window), not a full face dial.
struct AnalogDreamScaleView: View {
    @Binding var weightKg: Double
    var boundsKg: ClosedRange<Double>
    var unitSystem: PreferredUnitSystem
    var ink: Color
    var steel: Color
    var accent: Color

    @State private var lastMinorTick: Int = .min
    @State private var lastMajorTick: Int = .min
    @State private var dragStartKg: Double?

    private let minorStepKg: Double = 0.5
    private let majorEvery: Int = 5
    /// Degrees of disc visible in the window (real scale slit).
    private let viewportDegrees: Double = 25
    /// Angular density: how many degrees per kg on the disc.
    private let degreesPerKg: Double = 5

    private var displayValue: Double {
        UnitFormat.mass(fromKg: weightKg, system: unitSystem)
    }

    /// Disc rotation so the selected weight sits under the static needle (12 o'clock).
    private var discRotation: Angle {
        .degrees(-(weightKg - boundsKg.lowerBound) * degreesPerKg)
    }

    private var tickCount: Int {
        max(Int(((boundsKg.upperBound - boundsKg.lowerBound) / minorStepKg).rounded()), 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Housing
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.93, green: 0.94, blue: 0.96),
                                Color(red: 0.82, green: 0.85, blue: 0.88)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(ink.opacity(0.16), lineWidth: 1.5)
                    )

                // Rotating disc clipped to a narrow window
                ZStack {
                    discFace
                        .rotationEffect(discRotation, anchor: .center)

                    // Soft vignette inside window
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.10),
                            Color.clear,
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
                }
                .frame(height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ink.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .frame(maxHeight: .infinity, alignment: .top)

                // STATIC marker / needle at viewport center
                VStack(spacing: 0) {
                    Capsule()
                        .fill(accent)
                        .frame(width: 3, height: 28)
                        .shadow(color: ink.opacity(0.35), radius: 1.5, y: 1)
                    TriangleMarker()
                        .fill(accent)
                        .frame(width: 12, height: 10)
                }
                .padding(.top, 10)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

                // Readout
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", displayValue))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .monospacedDigit()
                    Text(unitSystem.massLabel.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(steel)
                }
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 200)
            .contentShape(Rectangle())
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

            Text("Drag. Marks move. Needle stays.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(steel)
        }
    }

    private var discFace: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height + size.width * 0.55)
            let radius = size.width * 0.92
            let halfWindow = viewportDegrees / 2
            // Draw a wide band of ticks so rotation always has marks in the window.
            let padTicks = Int((halfWindow / (degreesPerKg * minorStepKg)).rounded()) + 4

            for i in -padTicks...(tickCount + padTicks) {
                let kg = boundsKg.lowerBound + Double(i) * minorStepKg
                let degFromZero = Double(i) * minorStepKg * degreesPerKg
                // At rotation 0, lowerBound sits at 12 o'clock (-90° in standard math → top).
                let deg = -90 + degFromZero
                let rad = deg * .pi / 180
                let isMajor = i % majorEvery == 0
                let outer = radius
                let inner = radius - (isMajor ? 22 : 12)
                let cosA = Darwin.cos(rad)
                let sinA = Darwin.sin(rad)
                var path = Path()
                path.move(to: CGPoint(x: center.x + cosA * inner, y: center.y + sinA * inner))
                path.addLine(to: CGPoint(x: center.x + cosA * outer, y: center.y + sinA * outer))
                context.stroke(
                    path,
                    with: .color(isMajor ? ink.opacity(0.72) : steel.opacity(0.42)),
                    lineWidth: isMajor ? 2.2 : 1.1
                )

                if isMajor, kg >= boundsKg.lowerBound - 0.01, kg <= boundsKg.upperBound + 0.01 {
                    let labelKg = min(max(kg, boundsKg.lowerBound), boundsKg.upperBound)
                    let label = UnitFormat.mass(fromKg: labelKg, system: unitSystem)
                    let labelR = radius - 34
                    let pt = CGPoint(x: center.x + cosA * labelR, y: center.y + sinA * labelR)
                    let text = Text(String(format: "%.0f", label))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ink.opacity(0.7))
                    context.draw(text, at: pt, anchor: .center)
                }
            }
        }
        .frame(width: 320, height: 160)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartKg == nil {
                    dragStartKg = weightKg
                }
                guard let start = dragStartKg else { return }
                // Horizontal drag rotates the disc under the needle.
                // Positive dx → disc rotates clockwise → lower weight under needle.
                let kgDelta = -Double(value.translation.width) / degreesPerKg
                let raw = start + kgDelta
                let snapped = (raw / minorStepKg).rounded() * minorStepKg
                setKg(snapped)
            }
            .onEnded { _ in
                dragStartKg = nil
            }
    }

    private func setKg(_ kg: Double) {
        let clamped = min(max(kg, boundsKg.lowerBound), boundsKg.upperBound)
        let snapped = (clamped / minorStepKg).rounded() * minorStepKg
        let minorIndex = Int((snapped / minorStepKg).rounded())
        if minorIndex != lastMinorTick {
            lastMinorTick = minorIndex
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
            if minorIndex % majorEvery == 0, minorIndex != lastMajorTick {
                lastMajorTick = minorIndex
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.85)
            }
        }
        weightKg = snapped
    }
}

private struct TriangleMarker: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
