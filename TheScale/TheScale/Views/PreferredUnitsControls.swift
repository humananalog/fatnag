import SwiftUI

/// Independent mass + height pickers. Same control in onboarding and Settings.
struct PreferredUnitsControls: View {
    @Binding var units: PreferredUnitSystem
    var ink: Color
    var steel: Color
    var accent: Color
    var showLocationHint: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            unitPair(
                prompt: AppLanguageStore.text("units.weight.prompt", default: "Weight"),
                accessibility: "units.mass",
                leftTitle: "kg",
                rightTitle: "lb",
                rightSelected: units.usesImperialMass,
                onSelectRight: { imperial in
                    units = .combining(massImperial: imperial, heightImperial: units.usesImperialHeight)
                }
            )
            unitPair(
                prompt: AppLanguageStore.text("units.height.prompt", default: "Height"),
                accessibility: "units.height",
                leftTitle: "cm",
                rightTitle: "in",
                rightSelected: units.usesImperialHeight,
                onSelectRight: { imperial in
                    units = .combining(massImperial: units.usesImperialMass, heightImperial: imperial)
                }
            )
            if showLocationHint {
                Text(UnitPreferenceDefaults.suggestionCaption())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("units.locationHint")
            }
        }
    }

    private func unitPair(
        prompt: String,
        accessibility: String,
        leftTitle: String,
        rightTitle: String,
        rightSelected: Bool,
        onSelectRight: @escaping (Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
            HStack(spacing: 10) {
                chip(title: leftTitle, selected: !rightSelected, accessibility: "\(accessibility).metric") {
                    onSelectRight(false)
                }
                chip(title: rightTitle, selected: rightSelected, accessibility: "\(accessibility).imperial") {
                    onSelectRight(true)
                }
            }
        }
        .accessibilityIdentifier(accessibility)
    }

    private func chip(title: String, selected: Bool, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? Color.white : ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    selected ? accent : Color.white.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ink.opacity(selected ? 0 : 0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibility)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
