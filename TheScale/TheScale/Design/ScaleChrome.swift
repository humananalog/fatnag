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
