import SwiftUI

/// Destinations for the home liquid-glass nav (Keel / The Scale).
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

    var isCenter: Bool { self == .keel }
}

/// Home bottom nav following Apple Liquid Glass guidance:
/// - Prefer one glass surface (Adopting Liquid Glass / Applying Liquid Glass to custom views)
/// - No glass-on-glass (no `.buttonStyle(.glass)` stacked on an outer `glassEffect`)
/// - System hit targets (≥44pt), safe-area inset, black-tinted regular glass
/// Docs: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
///       https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
struct HomeGlassBar: View {
    let onSelect: (HomeGlassDestination) -> Void
    @State private var selected: HomeGlassDestination = .weigh

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassBar
            } else {
                fallbackBar
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The Scale navigation")
    }

    /// Single floating glass capsule (system tab-bar pattern) with an in-bar selection well.
    @available(iOS 26.0, *)
    private var liquidGlassBar: some View {
        HStack(spacing: 0) {
            ForEach(HomeGlassDestination.allCases) { dest in
                tabButton(dest, emphasizeKeel: true)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .glassEffect(
            .regular.tint(Color.black.opacity(0.48)).interactive(),
            in: Capsule(style: .continuous)
        )
    }

    private var fallbackBar: some View {
        HStack(spacing: 0) {
            ForEach(HomeGlassDestination.allCases) { dest in
                tabButton(dest, emphasizeKeel: true)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
    }

    private func tabButton(_ dest: HomeGlassDestination, emphasizeKeel: Bool) -> some View {
        let isSelected = selected == dest
        let isKeel = dest.isCenter
        let iconSize: CGFloat = {
            if isKeel { return isSelected ? 22 : 20 }
            return 17
        }()

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selected = dest
            }
            onSelect(dest)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: dest.systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: isSelected && isKeel)
                Text(dest.title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(foreground(for: dest, selected: isSelected))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(selectionFill(for: dest))
                        .padding(.horizontal, 2)
                        .padding(.vertical, 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dest.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func foreground(for dest: HomeGlassDestination, selected: Bool) -> Color {
        if dest.isCenter {
            return selected ? ScaleChrome.ember : Color.white.opacity(0.92)
        }
        return selected ? Color.white : Color.white.opacity(0.72)
    }

    private func selectionFill(for dest: HomeGlassDestination) -> Color {
        if dest.isCenter {
            return ScaleChrome.ember.opacity(0.28)
        }
        return Color.white.opacity(0.16)
    }
}

extension View {
    /// Shared black-tinted liquid glass capsule (single surface; no nested glass).
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
