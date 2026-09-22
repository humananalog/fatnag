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

    var isCenter: Bool { self == .keel }
}

/// Native liquid glass home bar (iOS 26+ `GlassEffectContainer` + `glassEffect` / `.glass` buttons).
struct HomeGlassBar: View {
    let onSelect: (HomeGlassDestination) -> Void
    @Namespace private var glassNamespace
    @State private var keelPulse = false

    private let sideDestinations: [HomeGlassDestination] = [.weigh, .progress]
    private let trailingDestinations: [HomeGlassDestination] = [.meals, .settings]

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                nativeGlassBar
            } else {
                fallbackBar
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The Scale navigation")
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                keelPulse = true
            }
        }
    }

    @available(iOS 26.0, *)
    private var nativeGlassBar: some View {
        // Official Liquid Glass: container morphs sibling glassEffect IDs (tab-bar style magnify).
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(sideDestinations) { dest in
                    sideGlassButton(dest)
                }

                keelGlassButton

                ForEach(trailingDestinations) { dest in
                    sideGlassButton(dest)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .glassEffect(
            .regular.tint(Color.black.opacity(0.28)).interactive(),
            in: Capsule(style: .continuous)
        )
    }

    @available(iOS 26.0, *)
    private func sideGlassButton(_ dest: HomeGlassDestination) -> some View {
        Button {
            onSelect(dest)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: dest.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(dest.title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
        .glassEffectID(dest.id, in: glassNamespace)
        .accessibilityLabel(dest.title)
    }

    @available(iOS 26.0, *)
    private var keelGlassButton: some View {
        Button {
            onSelect(.keel)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: HomeGlassDestination.keel.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.pulse, options: .repeating.speed(0.35), isActive: true)
                    .scaleEffect(keelPulse ? 1.08 : 0.96)
                    .opacity(keelPulse ? 1.0 : 0.88)
                Text(HomeGlassDestination.keel.title)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(width: 72, height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
        .glassEffect(
            .regular.tint(ScaleChrome.ember.opacity(0.35)).interactive(),
            in: Circle()
        )
        .glassEffectID(HomeGlassDestination.keel.id, in: glassNamespace)
        .accessibilityLabel("Keel")
    }

    private var fallbackBar: some View {
        HStack(spacing: 0) {
            ForEach(HomeGlassDestination.allCases) { dest in
                Button {
                    onSelect(dest)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: dest.systemImage)
                            .font(.system(size: dest.isCenter ? 24 : 16, weight: .semibold))
                            .scaleEffect(dest.isCenter && keelPulse ? 1.06 : 1.0)
                        Text(dest.title)
                            .font(.system(size: dest.isCenter ? 10 : 9, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, dest.isCenter ? 12 : 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dest.title)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
    }
}

extension View {
    /// Black-tinted liquid glass capsule (shared chrome).
    @ViewBuilder
    func scaleBlackGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(
                    .regular.tint(Color.black.opacity(0.32)).interactive(),
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
