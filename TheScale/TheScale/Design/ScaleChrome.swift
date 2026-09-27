import SwiftUI

/// Liquid Glass (iOS 26+) with material fallback. Built against the iOS 27 SDK.
/// Accent chrome biases slightly by `ScalePaletteUniverse` when views pass sex.
enum ScaleChrome {
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let steel = Color(red: 0.42, green: 0.45, blue: 0.50)
    static let void = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let ember = Color(red: 0.92, green: 0.55, blue: 0.18)
    static let signal = Color(red: 0.35, green: 0.78, blue: 0.92)

    /// Ember accent biased to the active universe (Glacier cool amber vs Bloom copper).
    static func ember(for universe: ScalePaletteUniverse) -> Color {
        switch universe {
        case .glacierForge:
            return Color(red: 0.86, green: 0.62, blue: 0.28)
        case .bloomCopper:
            return Color(red: 0.92, green: 0.52, blue: 0.32)
        }
    }

    /// Signal accent biased to the active universe (teal ice vs soft rose signal).
    static func signal(for universe: ScalePaletteUniverse) -> Color {
        switch universe {
        case .glacierForge:
            return Color(red: 0.32, green: 0.78, blue: 0.90)
        case .bloomCopper:
            return Color(red: 0.90, green: 0.58, blue: 0.62)
        }
    }

    static var darkChatGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.08),
                Color(red: 0.08, green: 0.09, blue: 0.12),
                Color(red: 0.04, green: 0.05, blue: 0.07)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func darkChatGradient(for universe: ScalePaletteUniverse) -> LinearGradient {
        switch universe {
        case .glacierForge:
            return LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.07, blue: 0.10),
                    Color(red: 0.06, green: 0.09, blue: 0.13),
                    Color(red: 0.03, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .bloomCopper:
            return LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.05, blue: 0.07),
                    Color(red: 0.11, green: 0.07, blue: 0.09),
                    Color(red: 0.06, green: 0.04, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

extension View {
    @ViewBuilder
    func scaleGlassPanel(cornerRadius: CGFloat = 18) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func scaleGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func scaleGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Circle())
        } else {
            self.background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// Safe inputs for linear progress / gauge fills.
/// Spring / entrance animation can briefly drive values outside range; clamp before paint.
/// Prefer `ScaleBoundedProgress` over `ProgressView(value:total:)` — SwiftUI logs a console
/// warning whenever `ProgressView` is initialized (or spring-interpolated) outside `0...total`.
/// Ban: never reintroduce determinate `ProgressView(value:)` anywhere (see
/// `scripts/assert_no_determinate_progressview.py`). Indeterminate `ProgressView()` is fine.
enum ProgressBounds {
    /// Guarantees finite `value` in `0...total` and `total > 0`. NaN / inf / negative → 0; `total ≤ 0` → 1.
    static func clamp(_ value: Double, total: Double) -> (value: Double, total: Double) {
        let safeTotal = (total.isFinite && total > 0) ? total : 1
        guard value.isFinite else { return (0, safeTotal) }
        return (min(max(value, 0), safeTotal), safeTotal)
    }

    static func clampedValue(_ value: Double, total: Double) -> Double {
        clamp(value, total: total).value
    }

    /// GeometryReader / spring layout can hand NaN or negative sizes; never feed those to `.frame`.
    static func safeLength(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}

/// Linear quota / progress track that never touches `ProgressView(value:total:)`.
/// Clamps every paint so spring overshoot / bad ratios cannot warn.
struct ScaleBoundedProgress: View {
    var value: Double
    var total: Double = 100
    var tint: Color
    var track: Color = Color.primary.opacity(0.12)
    var height: CGFloat = 6

    var body: some View {
        let bounds = ProgressBounds.clamp(value, total: total)
        GeometryReader { geo in
            let trackWidth = ProgressBounds.safeLength(geo.size.width)
            let filled = ProgressBounds.safeLength(trackWidth * CGFloat(bounds.value / bounds.total))
            let minKnob = bounds.value > 0.001 ? height : 0
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(track)
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(filled, minKnob))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
