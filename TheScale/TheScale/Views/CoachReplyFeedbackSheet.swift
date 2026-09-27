import SwiftUI

/// Quick thumbs reason sheet for a Coach reply → Supabase `submit-feedback`.
struct CoachReplyFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let rating: ScaleFeedbackRating
    let turn: CoachChatTurn
    var planTier: String = ScalePlan.free.rawValue
    var onFinished: (() -> Void)?

    @State private var selectedReasons: Set<String> = []
    @State private var freeText = ""
    @State private var isSending = false
    @State private var errorLine: String?
    @State private var didSucceed = false
    @FocusState private var focused: Bool

    private var ink: Color {
        colorScheme == .dark
            ? Color(red: 0.96, green: 0.95, blue: 0.92)
            : ScaleChrome.ink
    }

    private var steel: Color {
        colorScheme == .dark
            ? Color(red: 0.70, green: 0.72, blue: 0.76)
            : ScaleChrome.steel
    }

    private var reasons: [String] {
        switch rating {
        case .up:
            return [
                "Helpful",
                "Accurate",
                "Right tone",
                "Actionable",
                "Felt personal",
            ]
        case .down:
            return [
                "Wrong / inaccurate",
                "Unhelpful",
                "Tone off",
                "Too generic",
                "Missed context",
                "Too long",
            ]
        }
    }

    private var title: String {
        rating == .up ? "What worked?" : "What missed?"
    }

    private var canSend: Bool {
        !selectedReasons.isEmpty || !freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if didSucceed {
                    thanksBlock
                        .padding(22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(title)
                                    .font(.system(size: 24, weight: .semibold, design: .serif))
                                    .foregroundStyle(ink)
                                Text("Tap a reason. Optional note.")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(steel)

                                FlowReasonChips(
                                    reasons: reasons,
                                    selected: $selectedReasons,
                                    ink: ink,
                                    steel: steel
                                )

                                TextField(
                                    rating == .up ? "Anything else? (optional)" : "What should Coach have done?",
                                    text: $freeText,
                                    axis: .vertical
                                )
                                .lineLimit(2...4)
                                .focused($focused)
                                .padding(14)
                                .scaleGlassPanel(cornerRadius: 14)
                                .accessibilityIdentifier("coachFeedback.freetext")

                                if let errorLine {
                                    Text(errorLine)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Color(red: 0.78, green: 0.28, blue: 0.22))
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        }
                        .scrollDismissesKeyboard(.interactively)

                        sendBar
                    }
                }
            }
            .background(atmosphere.ignoresSafeArea())
            .navigationTitle(rating == .up ? "Thumbs up" : "Thumbs down")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSucceed ? "Done" : "Close") { finish() }
                        .accessibilityIdentifier("coachFeedback.close")
                }
            }
        }
        // Tall enough that chips + pinned Send fit without hunting for the button.
        .presentationDetents([.fraction(0.62), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSending)
    }

    /// Always visible under the scroll content — never buried below the fold.
    private var sendBar: some View {
        VStack(spacing: 10) {
            Divider().opacity(0.35)
            Button {
                Task { await send() }
            } label: {
                HStack {
                    if isSending { ProgressView().controlSize(.small) }
                    Text(isSending ? "Sending…" : "Send")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSending || !canSend)
            .accessibilityIdentifier("coachFeedback.send")
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background(atmosphere)
    }

    private var thanksBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Got it")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
            Text("Thanks — this reply vote helps tune Coach.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
            Button("Done") { finish() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private var atmosphere: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.07, green: 0.08, blue: 0.10), Color(red: 0.04, green: 0.05, blue: 0.07)]
                : [Color(red: 0.96, green: 0.97, blue: 0.98), Color(red: 0.90, green: 0.93, blue: 0.95)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @MainActor
    private func send() async {
        errorLine = nil
        isSending = true
        defer { isSending = false }

        let note = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = selectedReasons.sorted()
        if !note.isEmpty { parts.append(note) }
        let composed: String
        if parts.isEmpty {
            composed = rating == .up ? "Thumbs up" : "Thumbs down"
        } else {
            composed = parts.joined(separator: " · ")
        }

        do {
            try await ScaleFeedbackService.submit(
                ScaleFeedbackPayload(
                    category: rating == .up ? .praise : .bug,
                    message: composed,
                    contact: nil,
                    source: .coachReply,
                    planTier: planTier,
                    rating: rating,
                    liveModel: turn.usedNetwork ? GrokClient.liveModel : nil,
                    onDeviceModel: OnDevicePolishBootstrap.combinedOnDeviceLabel,
                    replyExcerpt: String(turn.text.prefix(800)),
                    turnId: turn.id
                )
            )
            withAnimation(.easeOut(duration: 0.25)) {
                didSucceed = true
            }
        } catch {
            errorLine = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func finish() {
        onFinished?()
        dismiss()
    }
}

/// Simple wrapping chip row (no external layout dependency).
private struct FlowReasonChips: View {
    let reasons: [String]
    @Binding var selected: Set<String>
    let ink: Color
    let steel: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunked(reasons, size: 2), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { reason in
                        chip(reason)
                    }
                    if row.count == 1 { Spacer(minLength: 0) }
                }
            }
        }
    }

    private func chip(_ reason: String) -> some View {
        let on = selected.contains(reason)
        return Button {
            if on { selected.remove(reason) } else { selected.insert(reason) }
        } label: {
            Text(reason)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(on ? ink : steel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .scaleGlassPanel(cornerRadius: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(on ? ScaleChrome.signal.opacity(0.55) : .clear, lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("coachFeedback.reason.\(reason)")
    }

    private func chunked(_ items: [String], size: Int) -> [[String]] {
        stride(from: 0, to: items.count, by: size).map {
            Array(items[$0..<min($0 + size, items.count)])
        }
    }
}

#Preview {
    CoachReplyFeedbackSheet(
        rating: .down,
        turn: CoachChatTurn(kind: .assistant, text: "Sample coach reply for feedback."),
        planTier: "free"
    )
}
