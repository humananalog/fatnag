import SwiftUI

/// Liquid Glass (iOS 26+) with material fallback. Built against the iOS 27 SDK.
enum ScaleChrome {
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let steel = Color(red: 0.42, green: 0.45, blue: 0.50)
    static let void = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let ember = Color(red: 0.92, green: 0.55, blue: 0.18)
    static let signal = Color(red: 0.35, green: 0.78, blue: 0.92)

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
            let width = geo.size.width * CGFloat(bounds.value / bounds.total)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(track)
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(width, bounds.value > 0.001 ? height : 0))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
