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

    /// Left/right neighbors for edge swipe between menu pages.
    var previousPage: HomeGlassDestination? {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx > 0 else { return nil }
        return all[idx - 1]
    }

    var nextPage: HomeGlassDestination? {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx < all.count - 1 else { return nil }
        return all[idx + 1]
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

    /// Swipe left/right on a menu page to move to the adjacent tab.
    /// Requires a clearly horizontal drag so vertical scrolls and carousels stay intact.
    func homeMenuPageSwipe(
        selection: HomeGlassDestination,
        onSelect: @escaping (HomeGlassDestination) -> Void
    ) -> some View {
        modifier(HomeMenuPageSwipeModifier(selection: selection, onSelect: onSelect))
    }
}

private struct HomeMenuPageSwipeModifier: ViewModifier {
    let selection: HomeGlassDestination
    let onSelect: (HomeGlassDestination) -> Void

    @State private var didCommit = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 56, coordinateSpace: .local)
                    .onChanged { value in
                        guard !didCommit else { return }
                        guard shouldCommit(value) else { return }
                        if let page = targetPage(for: value) {
                            didCommit = true
                            onSelect(page)
                        }
                    }
                    .onEnded { _ in
                        didCommit = false
                    }
            )
            .sensoryFeedback(.selection, trigger: selection)
    }

    private func shouldCommit(_ value: DragGesture.Value) -> Bool {
        let dx = value.translation.width
        let dy = value.translation.height
        // Dominant horizontal, past threshold.
        return abs(dx) > 72 && abs(dx) > abs(dy) * 1.65
    }

    private func targetPage(for value: DragGesture.Value) -> HomeGlassDestination? {
        if value.translation.width < 0 {
            return selection.nextPage
        }
        return selection.previousPage
    }
}
