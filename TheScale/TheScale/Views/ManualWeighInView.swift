import SwiftUI

/// Travel / hotel mass-only log. No BLE, no impedance, no invented fat/lean.
///
/// Sparse SpaceX-AI: Manual badge, large kg field, optional when, one Save.
struct ManualWeighInView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var weightText: String = ""
    @State private var occurredAt: Date = Date()
    @State private var showDatePicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var weightFocused: Bool

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.42, green: 0.45, blue: 0.50)
    private let horizontalInset: CGFloat = 28

    private var parsedKg: Double? {
        let normalized = weightText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0.05, value < 400 else { return nil }
        return value
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 20)
            hero
            Spacer(minLength: 24)
            controls
            Spacer(minLength: 12)
            saveButton
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 0.98),
                    Color(red: 0.90, green: 0.92, blue: 0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .preferredColorScheme(.light)
        .onAppear {
            if weightText.isEmpty, let baseline = session.healthBaselineKg {
                weightText = String(format: "%.1f", baseline)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                weightFocused = true
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
                    .fontWeight(.semibold)
            }
        }
        .alert("Could not save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                session.dismissManualEntry()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ink.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close manual entry")

            VStack(alignment: .leading, spacing: 2) {
                Text("Manual")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text("Mass only · no scale")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(steel)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("MANUAL")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(ink.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ink.opacity(0.08), in: Capsule())
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0.0", text: $weightText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.trailing)
                    .focused($weightFocused)
                    .minimumScaleFactor(0.45)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Weight in kilograms")

                Text("kg")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(steel)
            }

            Text("Writes weight and BMI to Apple Health. No body fat.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(steel.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    showDatePicker.toggle()
                }
            } label: {
                HStack {
                    Text("When")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink.opacity(0.75))
                    Spacer()
                    Text(occurredAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                    Image(systemName: showDatePicker ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(steel)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change date and time")

            if showDatePicker {
                DatePicker(
                    "When",
                    selection: $occurredAt,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                }
                Text(isSaving ? "Saving…" : "Save to Health")
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(
                (parsedKg == nil || isSaving) ? ink.opacity(0.35) : ink,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .disabled(parsedKg == nil || isSaving || !session.healthKitAvailable)
        .accessibilityHint("Saves mass only, then opens History")
    }

    private func save() async {
        guard let kg = parsedKg else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.saveManualWeight(kg: kg, at: occurredAt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ManualWeighInView()
        .environmentObject(ScaleSessionViewModel())
}
