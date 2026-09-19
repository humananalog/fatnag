import SwiftUI

/// First-launch profile: name, body basics, ideal weight, diet. On-device only.
struct OnboardingView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var name: String = ""
    @State private var heightCm: Double = 170
    @State private var ageYears: Double = 30
    @State private var sex: UserBodyProfile.Sex = .male
    @State private var idealKg: Double = UserBodyProfile.suggestedIdealWeightKg(heightCm: 170)
    @State private var diet: DietPreference = .omnivore
    @State private var step = 0

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.42, green: 0.45, blue: 0.50)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.96, blue: 0.98),
                    Color(red: 0.86, green: 0.89, blue: 0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Text("The Scale")
                    .font(.system(size: 36, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                Text(stepTitle)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(steel)

                Group {
                    switch step {
                    case 0:
                        nameStep
                    case 1:
                        bodyStep
                    default:
                        goalsStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Button(action: advance) {
                    Text(step < 2 ? "Continue" : "Let's go")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ink)
                .disabled(step == 0 && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(28)
        }
        .preferredColorScheme(.light)
        .onAppear {
            name = session.profile.displayName
            heightCm = session.profile.heightCm
            ageYears = session.profile.ageYears
            sex = session.profile.sex
            idealKg = session.profile.idealWeightKg
            diet = session.profile.dietPreference
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: return "What should we call you?"
        case 1: return "Body basics for on-device fat math."
        default: return "Ideal weight + how you eat."
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Your name", text: $name)
                .textContentType(.givenName)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .padding(.vertical, 10)
            Text("Stays on this iPhone. Coach uses it so we don't call you \"user\".")
                .font(.footnote)
                .foregroundStyle(steel)
        }
    }

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldRow("Height", unit: "cm", value: $heightCm, fraction: 0)
            fieldRow("Age", unit: "yr", value: $ageYears, fraction: 0)
            Picker("Sex", selection: $sex) {
                ForEach(UserBodyProfile.Sex.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            Text("Used only for local BIA math. Never uploaded.")
                .font(.caption)
                .foregroundStyle(steel)
        }
        .onChange(of: heightCm) { _, newValue in
            idealKg = UserBodyProfile.suggestedIdealWeightKg(heightCm: newValue)
        }
    }

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldRow("Ideal weight", unit: "kg", value: $idealKg, fraction: 1)
            Text("Diet preference")
                .font(.subheadline.weight(.semibold))
            Picker("Diet", selection: $diet) {
                ForEach(DietPreference.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.menu)
            Text("Optional Grok coaching later can use diet tone. Profile stays local unless you explicitly send a coach request.")
                .font(.caption)
                .foregroundStyle(steel)
        }
    }

    private func fieldRow(_ title: String, unit: String, value: Binding<Double>, fraction: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                unit,
                value: value,
                format: .number.precision(.fractionLength(fraction))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            Text(unit).foregroundStyle(steel)
        }
        .font(.body)
    }

    private func advance() {
        if step < 2 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                step += 1
            }
            return
        }
        session.profile = UserBodyProfile(
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            heightCm: heightCm,
            ageYears: ageYears,
            sex: sex,
            idealWeightKg: idealKg,
            idealBodyFatPercent: session.profile.idealBodyFatPercent,
            dietPreference: diet
        )
        OnboardingStore.hasCompleted = true
        session.hasCompletedOnboarding = true
    }
}

#Preview {
    OnboardingView()
        .environmentObject(ScaleSessionViewModel())
}
