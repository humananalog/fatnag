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
        case .weigh: return AppLanguageStore.text("tab.weigh", default: "Weigh")
        case .progress: return AppLanguageStore.text("tab.progress", default: "Progress")
        case .keel: return AppLanguageStore.text("tab.keel", default: "Keel")
        case .meals: return AppLanguageStore.text("tab.meals", default: "Meals")
        case .settings: return AppLanguageStore.text("tab.settings", default: "Settings")
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

    /// Settings keeps horizontal drags for the dream dial and form controls.
    var allowsMenuPageSwipe: Bool {
        self != .settings
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
    /// iOS 26 shrinks the tab bar on scroll; iOS 18 (iPhone XR) keeps the standard bar.
    @ViewBuilder
    func scaleTabBarMinimizeOnScrollDown() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

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
        if !selection.allowsMenuPageSwipe {
            content
        } else if selection == .meals {
            // Meal cards own horizontal drags. Page changes there start at the screen edge only.
            content
                .overlay(alignment: .leading) {
                    Color.clear
                        .frame(width: 22)
                        .contentShape(Rectangle())
                        .highPriorityGesture(pageDrag)
                }
                .overlay(alignment: .trailing) {
                    Color.clear
                        .frame(width: 22)
                        .contentShape(Rectangle())
                        .highPriorityGesture(pageDrag)
                }
                .sensoryFeedback(.selection, trigger: selection)
        } else {
            content
                .simultaneousGesture(pageDrag)
                .sensoryFeedback(.selection, trigger: selection)
        }
    }

    private var pageDrag: some Gesture {
        DragGesture(minimumDistance: 56, coordinateSpace: .local)
            .onChanged { value in
                guard !didCommit else { return }
                guard shouldCommit(value) else { return }
                if let page = targetPage(for: value) {
                    didCommit = true
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        onSelect(page)
                    }
                }
            }
            .onEnded { _ in
                didCommit = false
            }
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
