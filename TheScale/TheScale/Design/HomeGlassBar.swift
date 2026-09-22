import SwiftUI

/// Root destinations for the system liquid-glass tab bar (Weigh · Progress · Keel · Meals · Settings).
enum HomeGlassDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case weigh
    case progress
    case keel
    case meals
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weigh: return "Weigh"
        case .progress: return "Progress"
        case .keel: return "Keel"
        case .meals: return "Meals"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .weigh: return "scalemass.fill"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .keel: return "sparkles"
        case .meals: return "fork.knife"
        case .settings: return "gearshape.fill"
        }
    }
}

extension View {
    /// Shared black-tinted liquid glass capsule for floating chrome (not the tab bar).
    @ViewBuilder
    func scaleBlackGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.tint(Color.black.opacity(0.45)).interactive(),
                in: Capsule(style: .continuous)
            )
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
        }
    }
}
