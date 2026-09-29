import SwiftUI
import UIKit

/// Real bathroom-scale UX: fixed marker at 12 o'clock; dial disc rotates under it.
/// Tick spacing and major/minor marks follow metric (kg) or imperial (lb).
/// Disc labels are oriented so each number reads upright when that mark sits under the needle.
struct AnalogDreamScaleView: View {
    @Binding var weightKg: Double
    var boundsKg: ClosedRange<Double>
    var unitSystem: PreferredUnitSystem
    var ink: Color
    var steel: Color
    var accent: Color
    var accessibilityId: String = "onboarding.dream.analog"
    var caption: String = "Drag. Marks move. Needle stays."
    /// Called when a drag ends (or accessibility adjust settles) with the committed kg.
    var onCommit: ((Double) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var lastMinorTick: Int = .min
    @State private var lastMajorTick: Int = .min
    @State private var dragStartDisplay: Double?

    /// Minor step in the active display unit (kg or lb).
    private var minorStepDisplay: Double {
        unitSystem == .metric ? 0.5 : 1.0
    }

    /// Major marks land on round values: 70 / 75 / 80 kg, or 150 / 155 / 160 lb.
    private var majorStepDisplay: Double { 5.0 }

    /// Degrees of disc per display unit (kg or lb).
    private var degreesPerDisplay: Double {
        unitSystem == .metric ? 5 : 2.5
    }

    private let viewportDegrees: Double = 25
    private let discSide: CGFloat = 520
    private let tickRadius: CGFloat = 240
    private let windowHeight: CGFloat = 88
    private let housingHeight: CGFloat = 200
    private let maxHousingWidth: CGFloat = 420

    private var boundsDisplay: ClosedRange<Double> {
        let lo = UnitFormat.mass(fromKg: boundsKg.lowerBound, system: unitSystem)
        let hi = UnitFormat.mass(fromKg: boundsKg.upperBound, system: unitSystem)
        return min(lo, hi)...max(lo, hi)
    }

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

    private var discRotation: Angle {
        .degrees(-(displayValue - boundsDisplay.lowerBound) * degreesPerDisplay)
    }

    private var discWindowOffsetY: CGFloat {
        tickRadius - windowHeight * 0.35
    }

    private var tickCount: Int {
        max(Int(((boundsDisplay.upperBound - boundsDisplay.lowerBound) / minorStepDisplay).rounded()), 1)
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
                    let step = minorStepDisplay
                    switch direction {
                    case .increment:
                        setDisplay(displayValue + step, commit: true)
                    case .decrement:
                        setDisplay(displayValue - step, commit: true)
                    @unknown default:
                        break
                    }
                }
                .onChange(of: boundsKg.lowerBound) { _, _ in
                    setDisplay(displayValue, commit: false)
                }
                .onChange(of: boundsKg.upperBound) { _, _ in
                    setDisplay(displayValue, commit: false)
                }
                .onChange(of: unitSystem) { _, _ in
                    setDisplay(displayValue, commit: false)
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

            Color.clear
                .frame(height: windowHeight)
                .frame(maxWidth: .infinity)
                .overlay {
                    discFace
                        .frame(width: discSide, height: discSide)
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

            VStack(spacing: 0) {
                // Grey pointer only. No teal shaft.
                TriangleMarker()
                    .fill(steel.opacity(colorScheme == .dark ? 0.92 : 0.78))
                    .frame(width: 16, height: 14)
                    .shadow(color: ink.opacity(0.25), radius: 1.2, y: 1)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            VStack(spacing: 2) {
                Text(String(format: unitSystem == .metric ? "%.1f" : "%.0f", displayValue))
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

    private var discFace: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = tickRadius
            let halfWindow = viewportDegrees / 2
            let padTicks = Int((halfWindow / (degreesPerDisplay * minorStepDisplay)).rounded()) + 8

            for i in -padTicks...(tickCount + padTicks) {
                let display = boundsDisplay.lowerBound + Double(i) * minorStepDisplay
                let inBand = display >= boundsDisplay.lowerBound - 0.01
                    && display <= boundsDisplay.upperBound + 0.01
                let degFromZero = Double(i) * minorStepDisplay * degreesPerDisplay
                // 0° = +x (3 o'clock), -90° = 12 o'clock.
                let deg = -90 + degFromZero
                let rad = deg * .pi / 180
                let isMajor = isMajorDisplay(display)
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
                    let labelValue = min(max(display, boundsDisplay.lowerBound), boundsDisplay.upperBound)
                    let labelR = radius - 38
                    let pt = CGPoint(x: center.x + cosA * labelR, y: center.y + sinA * labelR)
                    let labelText = unitSystem == .metric
                        ? String(format: "%.0f", labelValue)
                        : String(format: "%.0f", labelValue.rounded())
                    let text = Text(labelText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ink.opacity(0.78))
                    // Rotate so the glyph is upright when this mark sits under the top needle.
                    // At 12 o'clock (deg = -90), text rotation = 0.
                    context.drawLayer { layer in
                        layer.translateBy(x: pt.x, y: pt.y)
                        layer.rotate(by: .degrees(deg + 90))
                        layer.draw(text, at: .zero, anchor: .center)
                    }
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartDisplay == nil {
                    dragStartDisplay = displayValue
                }
                guard let start = dragStartDisplay else { return }
                let delta = -Double(value.translation.width) / degreesPerDisplay
                let raw = start + delta
                let snapped = (raw / minorStepDisplay).rounded() * minorStepDisplay
                setDisplay(snapped, commit: false)
            }
            .onEnded { _ in
                dragStartDisplay = nil
                onCommit?(weightKg)
            }
    }

    private func setDisplay(_ display: Double, commit: Bool) {
        let clamped = min(max(display, boundsDisplay.lowerBound), boundsDisplay.upperBound)
        var snapped = (clamped / minorStepDisplay).rounded() * minorStepDisplay
        snapped = min(max(snapped, boundsDisplay.lowerBound), boundsDisplay.upperBound)
        let minorIndex = Int((snapped / minorStepDisplay).rounded())
        if minorIndex != lastMinorTick {
            lastMinorTick = minorIndex
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
            if isMajorDisplay(snapped) {
                let majorIndex = Int((snapped / majorStepDisplay).rounded())
                if majorIndex != lastMajorTick {
                    lastMajorTick = majorIndex
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.85)
                }
            }
        }
        let kg = UnitFormat.kg(fromMass: snapped, system: unitSystem)
        let kgClamped = min(max(kg, boundsKg.lowerBound), boundsKg.upperBound)
        if abs(weightKg - kgClamped) > 0.001 {
            weightKg = kgClamped
        }
        if commit {
            onCommit?(weightKg)
        }
    }
    private func isMajorDisplay(_ display: Double) -> Bool {
        AnalogScaleMarks.isMajor(display: display, majorStep: majorStepDisplay)
    }
}

/// Round major marks (70 / 75 / 80), not whatever the lower bound happens to be.
enum AnalogScaleMarks {
    static func isMajor(display: Double, majorStep: Double = 5) -> Bool {
        guard majorStep > 0 else { return false }
        let nearest = (display / majorStep).rounded() * majorStep
        return abs(display - nearest) < 0.001
    }
}

private struct TriangleMarker: Shape {
    /// Tip points down toward the dial.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
