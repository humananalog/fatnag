import SwiftUI
import UIKit

/// Age 18...100. Swipe / drag to change. Stepper is secondary, not the only path.
struct AgeSwipeControl: View {
    @Binding var ageYears: Double
    var ink: Color
    var steel: Color
    var accent: Color

    private let minAge: Double = 18
    private let maxAge: Double = 100

    @State private var dragStart: Double?
    @State private var lastHapticAge: Int = .min

    private var ageInt: Int {
        Int(ageYears.rounded())
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(AppLanguageStore.text("onboarding.age.label", default: "AGE"))
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(steel)

            HStack(spacing: 18) {
                Button {
                    bump(-1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.65), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.age.decrement")

                Text(ageYears < minAge ? "--" : "\(ageInt)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .frame(minWidth: 110)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .accessibilityIdentifier("onboarding.age")
                    .accessibilityLabel(AppLanguageStore.text("onboarding.age.a11y", default: "Age"))
                    .accessibilityValue(
                        ageYears < minAge
                            ? AppLanguageStore.text("onboarding.age.not_set", default: "not set")
                            : String(
                                format: AppLanguageStore.text("onboarding.age.years_a11y", default: "%d years"),
                                ageInt
                            )
                    )
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: bump(1)
                        case .decrement: bump(-1)
                        @unknown default: break
                        }
                    }

                Button {
                    bump(1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.65), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.age.increment")
            }

            // Swipe track
            GeometryReader { geo in
                let trackWidth = ProgressBounds.safeLength(geo.size.width)
                let fraction: CGFloat = {
                    guard ageYears >= minAge else { return 0 }
                    let span = maxAge - minAge
                    guard span > 0 else { return 0 }
                    return CGFloat((ageYears - minAge) / span)
                }()
                let fillWidth = ProgressBounds.safeLength(trackWidth * fraction)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ink.opacity(0.12))
                    Capsule()
                        .fill(accent.opacity(0.85))
                        .frame(width: max(8, fillWidth))
                    Circle()
                        .fill(ink)
                        .frame(width: 18, height: 18)
                        .offset(x: max(0, fillWidth - 9))
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard trackWidth > 0 else { return }
                            let t = min(max(value.location.x / trackWidth, 0), 1)
                            setAge(minAge + Double(t) * (maxAge - minAge))
                        }
                )
            }
            .frame(height: 18)
            .padding(.horizontal, 8)

            Text("Swipe or drag · 18-100")
                .font(.caption.weight(.semibold))
                .foregroundStyle(steel)
        }
        .accessibilityIdentifier("onboarding.age.swipe")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = max(ageYears, minAge)
                }
                guard let start = dragStart else { return }
                // Vertical: up = older. Horizontal also works.
                let delta = (-value.translation.height + value.translation.width) / 12
                setAge(start + delta)
            }
            .onEnded { _ in
                dragStart = nil
            }
    }

    private func bump(_ step: Double) {
        let base = ageYears < minAge ? minAge : ageYears
        setAge(base + step)
    }

    private func setAge(_ raw: Double) {
        let clamped = min(max(raw.rounded(), minAge), maxAge)
        let asInt = Int(clamped)
        if asInt != lastHapticAge {
            lastHapticAge = asInt
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
            if asInt % 10 == 0 {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
            }
        }
        ageYears = clamped
    }
}
