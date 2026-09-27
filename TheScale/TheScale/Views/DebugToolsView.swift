import SwiftUI

#if DEBUG
/// Always-visible DEBUG sheet for QA: reset onboarding, review prompts, Monday card.
struct DebugToolsView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var note: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Onboarding") {
                    Button("Reset onboarding & relaunch flow") {
                        OnboardingStore.hasCompleted = false
                        session.hasCompletedOnboarding = false
                        note = "Onboarding reset. Close this sheet."
                        dismiss()
                    }
                    .accessibilityIdentifier("debug.resetOnboarding")
                }
                Section("App Review") {
                    Button("Force soft star prompt") {
                        ScaleAppReviewPrompt.successfulWeighIns = max(
                            ScaleAppReviewPrompt.successfulWeighIns,
                            ScaleAppReviewPrompt.minimumWeighIns
                        )
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            session.isAppReviewPromptPresented = true
                        }
                    }
                    Button("Reset review prompt state") {
                        ScaleAppReviewPrompt.debugReset()
                        note = "Review state cleared."
                    }
                }
                Section("Monday / notifications") {
                    Button("Preview Monday card (ephemeral)") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            session.forcePresentMondayCard(regenerate: false)
                        }
                    }
                    Button("Regenerate Monday card (ephemeral)") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            session.forcePresentMondayCard(regenerate: true)
                        }
                    }
                    Button("Fire sample SOTA notification") {
                        Task {
                            let ok = await GrokFitnessMonitor.fireSampleSOTANotification(
                                profileName: session.profile.greetingName,
                                currentKg: session.healthBaselineKg
                            )
                            note = ok
                                ? "Sample ping scheduled (~1.5s)."
                                : "Sample ping failed. Allow notifications first."
                        }
                    }
                }
                Section("Apple Intelligence") {
                    Text(FoundationModelAvailability.statusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note {
                    Section {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("DEBUG")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
#endif
