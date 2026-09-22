import SwiftUI

/// Sparse Coach chat. One orchestrator voice; specialists consult behind the scenes.
struct CoachChatView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @StateObject private var chat = CoachChatController()
    @ObservedObject private var subscription = ScaleSubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivacyGate = false
    @FocusState private var focused: Bool

    private let messageFont = Font.system(size: 22, weight: .medium, design: .rounded)
    private let inputFont = Font.system(size: 20, weight: .medium, design: .rounded)

    var body: some View {
        VStack(spacing: 0) {
            header
            privacyLine
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(chat.turns) { turn in
                            bubble(turn).id(turn.id)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: chat.turns.count) { _, _ in
                    scrollToLatest(proxy)
                }
                .onChange(of: chat.turns.last?.text) { _, _ in
                    scrollToLatest(proxy)
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
        .alert("Send chat context to Keel?", isPresented: $showPrivacyGate) {
            Button("Cancel", role: .cancel) {}
            Button("Agree & send") {
                GrokPrivacyConsent.isAccepted = true
                Task { await chat.send(session: session) }
            }
        } message: {
            Text("Only this chat plus a short weight/fat/fitness digest go to the shared Keel backend. Memory stays on-device except the facts relevant to the ask. No per-user API key.")
        }
        .sheet(isPresented: $chat.showPaywall) {
            PaywallView(
                lockMessage: chat.paywallLockMessage,
                highlighted: chat.paywallHighlight
            )
            .environmentObject(session)
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        if let last = chat.turns.last {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
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
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                Text(statusLine)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
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
        if chat.isSending {
            return "Streaming…"
        }
        let snap = subscription.quotaSnapshot
        let quota = "\(snap.remaining)/\(snap.limit) wk"
        let fm = FoundationModelAvailability.shortLabel
        if GrokSharedConfig.isLiveConfigured {
            let mem = chat.rememberedCount
            let base = CoachPersona.liveBadge(memoryCount: mem)
            return "\(base) · \(quota) · \(fm)"
        }
        return "Mock / offline · \(quota) · \(fm)"
    }

    private var privacyLine: some View {
        Text(
            GrokPrivacyConsent.isAccepted
                ? "Consent on. \(subscription.quotaSnapshot.statusLine). Chat + compact Health digest + relevant memory only."
                : "Consent off until you agree (or stay offline)."
        )
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    private func bubble(_ turn: CoachChatTurn) -> some View {
        HStack {
            if turn.kind == .user { Spacer(minLength: 36) }
            VStack(alignment: turn.kind == .user ? .trailing : .leading, spacing: 6) {
                if turn.kind == .assistant {
                    HStack(spacing: 6) {
                        Text("COACH")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(ScaleChrome.ember.opacity(0.9))
                        if turn.usedNetwork {
                            Text("LIVE")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(ScaleChrome.signal)
                        }
                        if turn.isStreaming {
                            Text("STREAM")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(ScaleChrome.signal.opacity(0.75))
                        }
                        if turn.isFailure {
                            Text("ERROR")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.red.opacity(0.9))
                        }
                        if turn.isQuotaLock {
                            Text("LIMIT")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.orange.opacity(0.95))
                        }
                    }
                }
                Group {
                    if turn.kind == .assistant && turn.isStreaming && turn.text.isEmpty {
                        StreamingCursor()
                    } else {
                        Text(turn.text + (turn.isStreaming ? "▍" : ""))
                            .font(messageFont)
                            .foregroundStyle(turn.kind == .user ? ScaleChrome.void : .white.opacity(0.94))
                            .contentTransition(.interpolate)
                            .animation(.easeOut(duration: 0.12), value: turn.text)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                .font(inputFont)
                .lineLimit(1...5)
                .focused($focused)
                .padding(14)
                .scaleGlassPanel(cornerRadius: 16)
                .foregroundStyle(.white)

            Button {
                if GrokSharedConfig.isLiveConfigured && !GrokPrivacyConsent.isAccepted {
                    showPrivacyGate = true
                } else {
                    Task { await chat.send(session: session) }
                }
            } label: {
                Image(systemName: chat.isSending ? "hourglass" : "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(ScaleChrome.void)
                    .frame(width: 46, height: 46)
                    .background(ScaleChrome.ember, in: Circle())
            }
            .accessibilityLabel(chat.isSending ? "Sending" : "Send to Coach")
            .disabled(chat.isSending || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct StreamingCursor: View {
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(ScaleChrome.signal)
            .frame(width: 10, height: 18)
            .opacity(on ? 1 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    on = false
                }
            }
    }
}
