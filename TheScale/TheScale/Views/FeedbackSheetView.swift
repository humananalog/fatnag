import SwiftUI

/// Low-friction consumer feedback sheet. Category chips + short note + optional contact.
struct FeedbackSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var source: ScaleFeedbackSource = .settings
    var planTier: String = ScalePlan.free.rawValue
    var onFinished: (() -> Void)?

    @State private var category: ScaleFeedbackCategory = .idea
    @State private var message: String = ""
    @State private var contact: String = ""
    @State private var isSending = false
    @State private var errorLine: String?
    @State private var didSucceed = false
    @FocusState private var focused: Field?

    private enum Field { case message, contact }

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

    private var remaining: Int {
        ScaleFeedbackConfig.maxMessageLength - message.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if didSucceed {
                        thanksBlock
                    } else {
                        header
                        categoryRow
                        messageField
                        contactField
                        if let errorLine {
                            Text(errorLine)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color(red: 0.78, green: 0.28, blue: 0.22))
                                .accessibilityIdentifier("feedback.error")
                        }
                        sendButton
                        Text("Goes to Human Analog · \(ScaleFeedbackConfig.feedbackInbox). No Apple ID. Anonymous device id only.")
                            .font(.caption2)
                            .foregroundStyle(steel.opacity(0.85))
                    }
                }
                .padding(22)
            }
            .background(atmosphere.ignoresSafeArea())
            .navigationTitle(didSucceed ? "Sent" : "Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSucceed ? "Done" : "Close") {
                        finish()
                    }
                    .accessibilityIdentifier("feedback.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSending)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            FatnagWordmark(size: 26, color: ink)
            Text("One tap for type, a short note, optional email. That’s it.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
        }
    }

    private var categoryRow: some View {
        HStack(spacing: 8) {
            ForEach(ScaleFeedbackCategory.allCases) { item in
                Button {
                    category = item
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(category == item ? ink : steel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .scaleGlassPanel(cornerRadius: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(category == item ? ScaleChrome.signal.opacity(0.55) : .clear, lineWidth: 1.2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityHint(item.subtitle)
                .accessibilityAddTraits(category == item ? .isSelected : [])
                .accessibilityIdentifier("feedback.category.\(item.rawValue)")
            }
        }
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(steel)
            TextField(
                "What’s on your mind?",
                text: $message,
                axis: .vertical
            )
            .lineLimit(4...8)
            .focused($focused, equals: .message)
            .padding(14)
            .scaleGlassPanel(cornerRadius: 14)
            .accessibilityIdentifier("feedback.message")

            Text("\(max(0, remaining)) left")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(remaining < 40 ? Color.orange : steel.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var contactField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reply email (optional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(steel)
            TextField("you@example.com", text: $contact)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .contact)
                .padding(14)
                .scaleGlassPanel(cornerRadius: 14)
                .accessibilityIdentifier("feedback.contact")
        }
    }

    private var sendButton: some View {
        Button {
            Task { await send() }
        } label: {
            HStack {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isSending ? "Sending…" : "Send feedback")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("feedback.send")
    }

    private var thanksBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Got it")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
            Text("Thanks — a human at Human Analog will read this. No survey spam, no follow-up unless you left an email.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
            Button("Done") { finish() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
                .accessibilityIdentifier("feedback.thanksDone")
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
        do {
            try await ScaleFeedbackService.submit(
                ScaleFeedbackPayload(
                    category: category,
                    message: message,
                    contact: contact,
                    source: source,
                    planTier: planTier
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

#Preview {
    FeedbackSheetView(planTier: "plus")
}
