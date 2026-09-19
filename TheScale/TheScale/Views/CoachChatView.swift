import SwiftUI

/// Sparse Coach chat. One orchestrator voice; specialists consult behind the scenes.
struct CoachChatView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @StateObject private var chat = CoachChatController()
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivacyGate = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            privacyLine
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(chat.turns) { turn in
                            bubble(turn).id(turn.id)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: chat.turns.count) { _, _ in
                    if let last = chat.turns.last {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            composer
        }
        .background(ScaleChrome.darkChatGradient.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            chat.seedWelcome(name: session.profile.greetingName)
            Task { _ = await session.runFitnessMonitorCheck(force: false) }
        }
        .alert("Send chat context to Grok?", isPresented: $showPrivacyGate) {
            Button("Cancel", role: .cancel) {}
            Button("Agree & send") {
                GrokPrivacyConsent.isAccepted = true
                Task { await chat.send(brief: session.makeCoachBrief()) }
            }
        } message: {
            Text("Only this chat plus a short weight/fat/fitness digest go to the shared Grok backend. Memory stays on-device except the facts relevant to the ask. No per-user API key.")
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .scaleGlassCircle()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Coach")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                Text(statusLine)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(ScaleChrome.signal.opacity(0.85))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var statusLine: String {
        if let issue = GrokSharedConfig.configurationIssue, case .malformedProxyURL = issue {
            return "Proxy URL broken"
        }
        if GrokSharedConfig.isLiveConfigured {
            let mem = chat.rememberedCount
            return mem > 0 ? "Grok · \(mem) memories" : "Grok · live"
        }
        return "Mock / offline"
    }

    private var privacyLine: some View {
        Text(
            GrokPrivacyConsent.isAccepted
                ? "Consent on. Chat + compact Health digest + relevant memory only."
                : "Consent off until you agree (or stay offline)."
        )
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    private func bubble(_ turn: CoachChatTurn) -> some View {
        HStack {
            if turn.kind == .user { Spacer(minLength: 36) }
            VStack(alignment: turn.kind == .user ? .trailing : .leading, spacing: 4) {
                if turn.kind == .assistant {
                    HStack(spacing: 6) {
                        Text("COACH")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(ScaleChrome.ember.opacity(0.9))
                        if turn.usedNetwork {
                            Text("LIVE")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(ScaleChrome.signal)
                        }
                        if turn.isFailure {
                            Text("ERROR")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.red.opacity(0.9))
                        }
                    }
                }
                Text(turn.text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(turn.kind == .user ? ScaleChrome.void : .white.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                turn.isFailure
                                    ? Color.red.opacity(0.22)
                                    : (turn.kind == .user ? ScaleChrome.signal : Color.white.opacity(0.08))
                            )
                    )
            }
            if turn.kind != .user { Spacer(minLength: 36) }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask something sharp…", text: $chat.draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(12)
                .scaleGlassPanel(cornerRadius: 14)
                .foregroundStyle(.white)

            Button {
                if GrokSharedConfig.isLiveConfigured && !GrokPrivacyConsent.isAccepted {
                    showPrivacyGate = true
                } else {
                    Task { await chat.send(brief: session.makeCoachBrief()) }
                }
            } label: {
                Image(systemName: chat.isSending ? "hourglass" : "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(ScaleChrome.void)
                    .frame(width: 42, height: 42)
                    .background(ScaleChrome.ember, in: Circle())
            }
            .disabled(chat.isSending || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
