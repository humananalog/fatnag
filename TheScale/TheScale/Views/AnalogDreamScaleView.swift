import SwiftUI
import UIKit

/// Real bathroom-scale UX: fixed marker at 12 o'clock; dial disc rotates under it.
/// Pivot of rotation = true geometric center of the disc (same center ticks are drawn from).
/// Used by onboarding dream-weight and Settings target weight (same haptic control).
///
/// Layout note: the disc is intentionally larger than the housing (arc window). It must
/// live in an overlay so its square frame / rotationEffect never expand parent width
/// past the safe area (Settings sheet overflow).
struct AnalogDreamScaleView: View {
    @Binding var weightKg: Double
    var boundsKg: ClosedRange<Double>
    var unitSystem: PreferredUnitSystem
    var ink: Color
    var steel: Color
    var accent: Color
    var accessibilityId: String = "onboarding.dream.analog"
    var caption: String = "Drag. Marks move. Needle stays."

    @Environment(\.colorScheme) private var colorScheme
    @State private var lastMinorTick: Int = .min
    @State private var lastMajorTick: Int = .min
    @State private var dragStartKg: Double?

    private let minorStepKg: Double = 0.5
    private let majorEvery: Int = 5
    /// Degrees of disc visible in the reading window (real scale slit).
    private let viewportDegrees: Double = 25
    /// Angular density: how many degrees per kg on the disc circumference.
    private let degreesPerKg: Double = 5

    /// Full disc square — rotation pivot is its midpoint. Oversized on purpose;
    /// only a slit is visible. Never use this as a layout child of the housing.
    private let discSide: CGFloat = 520
    /// Tick ring radius from true disc center.
    private let tickRadius: CGFloat = 240
    /// Narrow reading window height (clips the 12 o'clock arc).
    private let windowHeight: CGFloat = 88
    /// Housing height (readout + window + padding).
    private let housingHeight: CGFloat = 200
    /// Cap dial width on large phones / iPad so it stays a dial, not a banner.
    private let maxHousingWidth: CGFloat = 420

    private var displayValue: Double {
        UnitFormat.mass(fromKg: weightKg, system: unitSystem)
    }

    private var housingColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.22, green: 0.24, blue: 0.28),
                Color(red: 0.14, green: 0.15, blue: 0.18)
            ]
        }
        return [
            Color(red: 0.93, green: 0.94, blue: 0.96),
            Color(red: 0.82, green: 0.85, blue: 0.88)
        ]
    }

    /// Disc rotation so the selected weight sits under the static needle (12 o'clock).
    /// Positive SwiftUI rotation is clockwise; increasing kg rotates CCW so the higher
    /// mark swings up under the fixed top marker.
    private var discRotation: Angle {
        .degrees(-(weightKg - boundsKg.lowerBound) * degreesPerKg)
    }

    /// How far to push the disc down so its 12 o'clock circumference sits in the window.
    /// Window ZStack is `windowHeight` tall and centers children; after this offset the
    /// disc's true center (rotation pivot) lies below the window, matching a real dial.
    private var discWindowOffsetY: CGFloat {
        tickRadius - windowHeight * 0.35
    }

    private var tickCount: Int {
        max(Int(((boundsKg.upperBound - boundsKg.lowerBound) / minorStepKg).rounded()), 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            housing
                .frame(maxWidth: maxHousingWidth)
                .frame(maxWidth: .infinity)
                .frame(height: housingHeight)
                .clipped()
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .accessibilityIdentifier(accessibilityId)
                .accessibilityLabel("Target weight \(String(format: "%.1f", displayValue)) \(unitSystem.massLabel)")
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
                .onChange(of: boundsKg.lowerBound) { _, _ in
                    setKg(weightKg)
                }
                .onChange(of: boundsKg.upperBound) { _, _ in
                    setKg(weightKg)
                }

            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(steel)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var housing: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: housingColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(ink.opacity(colorScheme == .dark ? 0.28 : 0.16), lineWidth: 1.5)
                )

            // Reading window: layout sized to housing; oversized disc is overlay-only
            // so discSide / rotationEffect never propose width past the safe area.
            Color.clear
                .frame(height: windowHeight)
                .frame(maxWidth: .infinity)
                .overlay {
                    discFace
                        .frame(width: discSide, height: discSide)
                        // Pivot = true disc center (same point ticks are drawn around).
                        .rotationEffect(discRotation, anchor: .center)
                        .offset(y: discWindowOffsetY)
                        .allowsHitTesting(false)
                }
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10),
                            Color.clear,
                            Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ink.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // STATIC marker at 12 o'clock — does not rotate with the disc
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// Full circular tick disc. Canvas center == view center == rotation pivot.
    private var discFace: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = tickRadius
            let halfWindow = viewportDegrees / 2
            // Draw a wide band of ticks so rotation always has marks in the window.
            let padTicks = Int((halfWindow / (degreesPerKg * minorStepKg)).rounded()) + 8

            for i in -padTicks...(tickCount + padTicks) {
                let kg = boundsKg.lowerBound + Double(i) * minorStepKg
                // Outside the hard band: still draw faint pad ticks for disc continuity,
                // but never label them as selectable values.
                let inBand = kg >= boundsKg.lowerBound - 0.01 && kg <= boundsKg.upperBound + 0.01
                let degFromZero = Double(i) * minorStepKg * degreesPerKg
                // Standard math: 0° = +x (3 o'clock), -90° = 12 o'clock (top).
                // At rotation 0, lowerBound sits under the fixed top marker.
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
                let tickOpacity = inBand ? (isMajor ? 0.72 : 0.42) : 0.18
                context.stroke(
                    path,
                    with: .color(isMajor ? ink.opacity(tickOpacity) : steel.opacity(tickOpacity)),
                    lineWidth: isMajor ? 2.2 : 1.1
                )

                if isMajor, inBand {
                    let labelKg = min(max(kg, boundsKg.lowerBound), boundsKg.upperBound)
                    let label = UnitFormat.mass(fromKg: labelKg, system: unitSystem)
                    let labelR = radius - 36
                    let pt = CGPoint(x: center.x + cosA * labelR, y: center.y + sinA * labelR)
                    let text = Text(String(format: "%.0f", label))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ink.opacity(0.7))
                    context.draw(text, at: pt, anchor: .center)
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartKg == nil {
                    dragStartKg = weightKg
                }
                guard let start = dragStartKg else { return }
                // Horizontal drag rotates the disc under the needle.
                // Positive dx → disc clockwise → lower weight under needle.
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
        var snapped = (clamped / minorStepKg).rounded() * minorStepKg
        snapped = min(max(snapped, boundsKg.lowerBound), boundsKg.upperBound)
        let minorIndex = Int((snapped / minorStepKg).rounded())
        if minorIndex != lastMinorTick {
            lastMinorTick = minorIndex
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
            if minorIndex % majorEvery == 0, minorIndex != lastMajorTick {
                lastMajorTick = minorIndex
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.85)
            }
        }
        if abs(weightKg - snapped) > 0.001 {
            weightKg = snapped
        }
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
