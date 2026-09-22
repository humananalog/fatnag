import SwiftUI

/// Destinations for the home liquid-glass nav bar (Keel / The Scale).
enum HomeGlassDestination: String, CaseIterable, Identifiable, Sendable {
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

/// Black-tinted liquid glass bar (iOS 26+ glassEffect; material fallback).
struct HomeGlassBar: View {
    let onSelect: (HomeGlassDestination) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeGlassDestination.allCases) { dest in
                Button {
                    onSelect(dest)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: dest.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        Text(dest.title)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dest.title)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .scaleBlackGlassCapsule()
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The Scale navigation")
    }
}

extension View {
    /// Black-tinted liquid glass capsule for the home glassbar.
    @ViewBuilder
    func scaleBlackGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(
                    .regular.tint(Color.black.opacity(0.55)).interactive(),
                    in: Capsule(style: .continuous)
                )
        } else {
            self
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.72))
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        }
                }
        }
    }
}
