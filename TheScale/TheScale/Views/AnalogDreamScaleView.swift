import SwiftUI
import UIKit

/// Real bathroom-scale UX: fixed marker at 12 o'clock; dial disc rotates under it.
/// Tick spacing and major/minor marks follow **only** the selected unit system
/// (kg **or** lb — never both rings at once). The minimum and maximum marks of
/// that unit's range sit on a 350° arc.
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
    @State private var lastLightHapticAt: Date = .distantPast
    @State private var lightHaptic = UIImpactFeedbackGenerator(style: .light)
    @State private var mediumHaptic = UIImpactFeedbackGenerator(style: .medium)

    /// Core Haptics rejects bursts above ~32 Hz — keep light ticks under that.
    private static let minLightHapticInterval: TimeInterval = 0.055

    /// Layout for the active unit only (never mixes kg + lb grids).
    private var layout: AnalogScaleLayout {
        AnalogScaleLayout.make(boundsKg: boundsKg, system: unitSystem)
    }

    private let viewportDegrees: Double = 28
    private let discSide: CGFloat = 520
    private let tickRadius: CGFloat = 240
    private let windowHeight: CGFloat = 88
    private let housingHeight: CGFloat = 200
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

    private var discRotation: Angle {
        // 0° puts the minimum mark under the needle; the maximum sits 350° around the disc.
        .degrees(-(displayValue - layout.boundsDisplay.lowerBound) * layout.degreesPerUnit)
    }

    private var discWindowOffsetY: CGFloat {
        tickRadius - windowHeight * 0.35
    }

    var body: some View {
        VStack(spacing: 10) {
            housing
                .frame(maxWidth: maxHousingWidth)
                .frame(maxWidth: .infinity)
                .frame(height: housingHeight)
                .clipped()
                .contentShape(Rectangle())
                // Win horizontal drags over the Settings ScrollView so the disc actually turns.
                .highPriorityGesture(dragGesture)
                .accessibilityIdentifier(accessibilityId)
                .accessibilityLabel("Target weight \(String(format: "%.1f", displayValue)) \(unitSystem.massLabel)")
                .accessibilityValue(String(format: "%.1f %@", displayValue, unitSystem.massLabel))
                .accessibilityAdjustableAction { direction in
                    let step = layout.minorStep
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
                    lastMinorTick = .min
                    lastMajorTick = .min
                    dragStartDisplay = nil
                    setDisplay(displayValue, commit: false)
                }

            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(steel)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        // Hard remount when units flip so kg and lb discs never composite together.
        .id("analog-scale-\(unitSystem.rawValue)")
        .transaction { $0.animation = nil }
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
                Text(String(format: unitSystem.usesImperialMass ? "%.0f" : "%.1f", displayValue))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unitSystem.massLabel.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(steel)
            }
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        }
    }

    private var discFace: some View {
        let layout = self.layout
        let system = unitSystem
        let inkColor = ink
        let steelColor = steel
        let radius = tickRadius
        let halfWindow = viewportDegrees / 2
        let padTicks = Int((halfWindow / (layout.degreesPerUnit * layout.minorStep)).rounded()) + 10

        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let step = layout.minorStep
            let origin = layout.alignedLower
            let majorStep = layout.majorStep
            let degreesPer = layout.degreesPerUnit
            let lo = layout.boundsDisplay.lowerBound
            let hi = layout.boundsDisplay.upperBound

            for i in -padTicks...(layout.tickCount + padTicks) {
                let display = origin + Double(i) * step
                // Only paint the selected unit's in-band marks — no ghost second ring.
                let inBand = display >= lo - 0.01 && display <= hi + 0.01
                guard inBand else { continue }

                let degFromZero = (display - lo) * degreesPer
                // 0° = +x (3 o'clock), -90° = 12 o'clock.
                let deg = -90 + degFromZero
                let rad = deg * .pi / 180
                let isMajor = AnalogScaleMarks.isMajor(display: display, majorStep: majorStep)
                let outer = radius
                let inner = radius - (isMajor ? 22 : 12)
                let cosA = Darwin.cos(rad)
                let sinA = Darwin.sin(rad)
                var path = Path()
                path.move(to: CGPoint(x: center.x + cosA * inner, y: center.y + sinA * inner))
                path.addLine(to: CGPoint(x: center.x + cosA * outer, y: center.y + sinA * outer))
                context.stroke(
                    path,
                    with: .color(isMajor ? inkColor.opacity(0.85) : steelColor.opacity(0.48)),
                    lineWidth: isMajor ? 2.4 : 1.15
                )

                if isMajor {
                    let labelR = radius - 40
                    let pt = CGPoint(x: center.x + cosA * labelR, y: center.y + sinA * labelR)
                    let labelText = AnalogScaleMarks.label(
                        display: display,
                        system: system
                    )
                    let text = Text(labelText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(inkColor.opacity(0.88))
                    let resolved = context.resolve(text)
                    // Rotate so the glyph is upright when this mark sits under the top needle.
                    context.drawLayer { layer in
                        layer.translateBy(x: pt.x, y: pt.y)
                        layer.rotate(by: .degrees(deg + 90))
                        layer.draw(resolved, at: .zero, anchor: .center)
                    }
                }
            }
        }
        .id("disc-\(system.rawValue)-\(layout.alignedLower)-\(layout.alignedUpper)-\(layout.tickCount)")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                // Prefer horizontal intent so vertical scroll still works outside the dial.
                if abs(value.translation.height) > abs(value.translation.width) * 1.35,
                   dragStartDisplay == nil {
                    return
                }
                if dragStartDisplay == nil {
                    dragStartDisplay = displayValue
                    lightHaptic.prepare()
                    mediumHaptic.prepare()
                }
                guard let start = dragStartDisplay else { return }
                let delta = -Double(value.translation.width) / layout.degreesPerUnit
                let raw = start + delta
                let snapped = (raw / layout.minorStep).rounded() * layout.minorStep
                setDisplay(snapped, commit: false)
            }
            .onEnded { _ in
                let hadDrag = dragStartDisplay != nil
                dragStartDisplay = nil
                if hadDrag {
                    onCommit?(weightKg)
                }
            }
    }

    private func setDisplay(_ display: Double, commit: Bool) {
        let layout = self.layout
        let clamped = min(max(display, layout.boundsDisplay.lowerBound), layout.boundsDisplay.upperBound)
        var snapped = (clamped / layout.minorStep).rounded() * layout.minorStep
        snapped = min(max(snapped, layout.boundsDisplay.lowerBound), layout.boundsDisplay.upperBound)
        let minorIndex = Int((snapped / layout.minorStep).rounded())
        if minorIndex != lastMinorTick {
            lastMinorTick = minorIndex
            let now = Date()
            if now.timeIntervalSince(lastLightHapticAt) >= Self.minLightHapticInterval {
                lastLightHapticAt = now
                lightHaptic.impactOccurred(intensity: 0.45)
            }
            if AnalogScaleMarks.isMajor(display: snapped, majorStep: layout.majorStep) {
                let majorIndex = Int((snapped / layout.majorStep).rounded())
                if majorIndex != lastMajorTick {
                    lastMajorTick = majorIndex
                    mediumHaptic.impactOccurred(intensity: 0.8)
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
}

/// Single-unit dial geometry. Built only for metric **or** imperial — never both.
struct AnalogScaleLayout: Equatable, Sendable {
    /// Min mark at 0° and max mark at this angle. The remaining 10° is the gap
    /// so the two ends do not sit on top of each other.
    static let dialArcDegrees: Double = 350

    var system: PreferredUnitSystem
    var minorStep: Double
    var majorStep: Double
    var degreesPerUnit: Double
    var boundsDisplay: ClosedRange<Double>
    var alignedLower: Double
    var alignedUpper: Double
    var tickCount: Int

    static func make(
        boundsKg: ClosedRange<Double>,
        system: PreferredUnitSystem
    ) -> AnalogScaleLayout {
        let defaultMinor: Double = system.usesImperialMass ? 1.0 : 0.5
        let lo = UnitFormat.mass(fromKg: boundsKg.lowerBound, system: system)
        let hi = UnitFormat.mass(fromKg: boundsKg.upperBound, system: system)
        let bounds = min(lo, hi)...max(lo, hi)
        let span = max(bounds.upperBound - bounds.lowerBound, defaultMinor)
        // Same 350° arc for every unit system; kg and lb just change how many
        // marks share that arc.
        let degrees = dialArcDegrees / span
        // Full 30–300 kg anatomy range used to pack hundreds of labels. Coarsen
        // so minor ticks stay ≥ ~2.2° — same readable density as Settings.
        let minMinorDegrees = 2.2
        var minor = defaultMinor
        if degrees * minor < minMinorDegrees {
            minor = niceMinorStep(minimum: minMinorDegrees / degrees, imperialMass: system.usesImperialMass)
        }
        let major = majorStep(forMinor: minor)
        let alignedLo = (bounds.lowerBound / minor).rounded(.down) * minor
        let alignedHi = (bounds.upperBound / minor).rounded(.up) * minor
        let count = max(Int(((alignedHi - alignedLo) / minor).rounded()), 1)
        return AnalogScaleLayout(
            system: system,
            minorStep: minor,
            majorStep: major,
            degreesPerUnit: degrees,
            boundsDisplay: bounds,
            alignedLower: alignedLo,
            alignedUpper: alignedHi,
            tickCount: count
        )
    }

    private static func niceMinorStep(minimum: Double, imperialMass: Bool) -> Double {
        let candidates: [Double] = imperialMass ? [1, 2, 5, 10, 20] : [0.5, 1, 2, 5, 10, 20]
        return candidates.first { $0 + 0.001 >= minimum } ?? (candidates.last ?? 20)
    }

    private static func majorStep(forMinor minor: Double) -> Double {
        if minor <= 1 { return 5 }
        if minor <= 2 { return 10 }
        if minor <= 5 { return 20 }
        return 50
    }

    /// In-band display values for the selected system only (testable).
    func displayTicks(includePad: Int = 0) -> [Double] {
        let start = -includePad
        let end = tickCount + includePad
        var values: [Double] = []
        values.reserveCapacity(end - start + 1)
        for i in start...end {
            let display = alignedLower + Double(i) * minorStep
            if display >= boundsDisplay.lowerBound - 0.01,
               display <= boundsDisplay.upperBound + 0.01 {
                values.append(display)
            }
        }
        return values
    }

    func majorLabels() -> [Double] {
        displayTicks().filter { AnalogScaleMarks.isMajor(display: $0, majorStep: majorStep) }
    }
}

/// Round major marks for **one** unit grid (70 / 75 / 80 kg, or 150 / 155 / 160 lb).
enum AnalogScaleMarks {
    static func isMajor(display: Double, majorStep: Double = 5) -> Bool {
        guard majorStep > 0 else { return false }
        let nearest = (display / majorStep).rounded() * majorStep
        return abs(display - nearest) < 0.05
    }

    static func label(display: Double, system: PreferredUnitSystem) -> String {
        // Numbers only — unit lives under the needle. Never emit a second-system conversion.
        _ = system
        return String(format: "%.0f", display.rounded())
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
