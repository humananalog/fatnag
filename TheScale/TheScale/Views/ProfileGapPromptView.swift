import SwiftUI

/// Soft one-question sheet to complete blank lifestyle fields over time.
struct ProfileGapPromptView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.42, green: 0.45, blue: 0.50)
    private let moss = Color(red: 0.12, green: 0.35, blue: 0.28)

    @State private var locationDraft = ""
    @State private var useLocalContext = true
    @State private var avoidDraft = ""
    @State private var dietDraft: DietPreference = .omnivore

    private var kind: ProfileGapKind? { session.pendingProfileGap }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let kind {
                    Text("OPTIONAL")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(moss)

                    Text(kind.title)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profileGap.title")

                    Text(kind.subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(steel)
                        .fixedSize(horizontal: false, vertical: true)

                    field(for: kind)
                        .padding(.top, 4)

                    Text("Skip anytime. We'll ask gently later, not every day.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(steel.opacity(0.85))
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button("Not now") {
                        session.skipProfileGap()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("profileGap.skip")

                    Button("Save") {
                        session.saveProfileGap(
                            location: locationDraft,
                            useLocalContext: useLocalContext,
                            foodAvoidances: avoidDraft,
                            diet: dietDraft
                        )
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ink)
                    .accessibilityIdentifier("profileGap.save")
                }
            }
            .padding(22)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        session.skipProfileGap()
                        dismiss()
                    }
                }
            }
            .onAppear {
                locationDraft = session.profile.location
                useLocalContext = session.profile.useLocalContext
                avoidDraft = session.profile.foodAvoidances
                dietDraft = session.profile.dietPreference
                if let kind = session.pendingProfileGap {
                    ProfileGapPromptEngine.recordPresented(kind)
                }
            }
        }
        .presentationDetents([.height(360), .medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func field(for kind: ProfileGapKind) -> some View {
        switch kind {
        case .location:
            VStack(alignment: .leading, spacing: 10) {
                TextField("City or area (e.g. Manila, Central HK)", text: $locationDraft)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("profileGap.location")
                Toggle("Use for local food and fitness context", isOn: $useLocalContext)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("profileGap.useLocal")
            }
        case .foodAvoidances:
            TextField("Peanuts, shellfish, no dairy…", text: $avoidDraft, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("profileGap.avoidances")
        case .diet:
            Picker("Diet", selection: $dietDraft) {
                ForEach(DietPreference.allCases) { diet in
                    Text(diet.title).tag(diet)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxHeight: 120)
            .accessibilityIdentifier("profileGap.diet")
        }
    }
}
