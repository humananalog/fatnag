import SwiftUI

/// Sparse Coach chat. One orchestrator voice; specialists consult behind the scenes.
struct CoachChatView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @StateObject private var chat = CoachChatController()
    @ObservedObject private var subscription = ScaleSubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivacyGate = false
    @State private var feedbackTarget: CoachFeedbackTarget?
    @FocusState private var focused: Bool

    private let messageFont = Font.system(size: 22, weight: .medium, design: .rounded)
    private let inputFont = Font.system(size: 20, weight: .medium, design: .rounded)

    private var universe: ScalePaletteUniverse {
        .resolve(sex: session.profile.sex)
    }

    private var signal: Color { ScaleChrome.signal(for: universe) }
    private var ember: Color { ScaleChrome.ember(for: universe) }

    var body: some View {
        VStack(spacing: 0) {
            header
            privacyLine
            if let notice = chat.transientNotice {
                transientBanner(notice)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(chat.turns) { turn in
                            bubble(turn).id(turn.id)
                        }
                    }
                    .padding(ScaleLayout.pageInset)
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
        .background(ScaleChrome.darkChatGradient(for: universe).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.55), value: session.profile.sex)
        .preferredColorScheme(.dark)
        .onAppear {
            chat.seedWelcome(name: session.profile.greetingName)
            Task { _ = await session.runFitnessMonitorCheck(force: false) }
        }
        .alert(
            AppLanguageStore.text("coach.privacy.title", default: "Send chat context to Keel?"),
            isPresented: $showPrivacyGate
        ) {
            Button(AppLanguageStore.text("common.cancel", default: "Cancel"), role: .cancel) {}
            Button(AppLanguageStore.text("coach.privacy.agree", default: "Agree & send")) {
                GrokPrivacyConsent.isAccepted = true
                Task { await chat.send(session: session) }
            }
        } message: {
            Text(AppLanguageStore.text("coach.privacy.body", default: "Only this chat plus a short weight/fat/fitness digest go to the shared Keel backend. Memory stays on-device except the facts relevant to the ask. No per-user API key."))
        }
        .sheet(isPresented: $chat.showPaywall) {
            PaywallView(
                lockMessage: chat.paywallLockMessage,
                highlighted: chat.paywallHighlight
            )
            .environmentObject(session)
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $feedbackTarget) { target in
            CoachReplyFeedbackSheet(
                rating: target.rating,
                turn: target.turn,
                planTier: subscription.plan.rawValue
            )
        }
        .onChange(of: chat.transientNotice) { _, notice in
            guard notice != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                await MainActor.run {
                    if chat.transientNotice == notice {
                        chat.clearTransientNotice()
                    }
                }
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        if let last = chat.turns.last {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func transientBanner(_ notice: String) -> some View {
        HStack(spacing: 10) {
            Text(notice)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                chat.clearTransientNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityLabel(AppLanguageStore.text("common.dismiss", default: "Dismiss"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.10))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .accessibilityIdentifier("coach.transientNotice")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLanguageStore.text("coach.title", default: "Coach"))
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                Text(statusLine)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Button { session.dismissCoach() } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 36, height: 36)
                    .scaleGlassCircle()
            }
            .accessibilityLabel(AppLanguageStore.text("common.dismiss", default: "Dismiss"))
        }
        .padding(.horizontal, ScaleLayout.pageInset)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var statusLine: String {
        if let issue = GrokSharedConfig.configurationIssue, case .malformedProxyURL = issue {
            return "Proxy URL broken"
        }
        if chat.isSending {
            return AppLanguageStore.text("coach.streaming", default: "Streaming…")
        }
        let snap = subscription.quotaSnapshot
        if GrokSharedConfig.isLiveConfigured {
            return "\(snap.remaining)/\(snap.limit) this week"
        }
        return AppLanguageStore.text("coach.offline", default: "Offline")
    }

    private var privacyLine: some View {
        Text(
            GrokPrivacyConsent.isAccepted
                ? String(
                    format: AppLanguageStore.text("coach.consent.on", default: "Consent on. %@. Chat + compact Health digest + relevant memory only."),
                    subscription.quotaSnapshot.statusLine
                )
                : AppLanguageStore.text("coach.consent.off", default: "Consent off until you agree (or stay offline).")
        )
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, ScaleLayout.pageInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    private func bubble(_ turn: CoachChatTurn) -> some View {
        HStack {
            if turn.kind == .user { Spacer(minLength: 36) }
            VStack(alignment: turn.kind == .user ? .trailing : .leading, spacing: 6) {
                if turn.kind == .assistant {
                    HStack(spacing: 6) {
                        Text(AppLanguageStore.text("coach.badge.coach", default: "COACH"))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(ember.opacity(0.9))
                        if turn.usedNetwork {
                            Text(AppLanguageStore.text("coach.badge.live", default: "LIVE"))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(signal)
                        }
                        if turn.isStreaming {
                            Text(AppLanguageStore.text("coach.badge.stream", default: "STREAM"))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(signal.opacity(0.75))
                        }
                        if turn.isQuotaLock {
                            Text(AppLanguageStore.text("coach.badge.limit", default: "LIMIT"))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.orange.opacity(0.95))
                        }
                    }
                }
                Group {
                    if turn.kind == .assistant && turn.isStreaming && turn.text.isEmpty {
                        StreamingCursor(tint: signal)
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
                            turn.isQuotaLock
                                ? Color.orange.opacity(0.22)
                                : (turn.kind == .user ? signal : Color.white.opacity(0.08))
                        )
                )
                .overlay(
                    Group {
                        if turn.isQuotaLock {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.55), lineWidth: 1)
                        }
                    }
                )
                if turn.isQuotaLock {
                    Text(AppLanguageStore.text("coach.unlock", default: "Tap to unlock Coach"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.orange.opacity(0.95))
                }
                if showsFeedback(for: turn) {
                    feedbackRow(for: turn)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard turn.isQuotaLock else { return }
                chat.openPaywall(from: turn)
            }
            .accessibilityAddTraits(turn.isQuotaLock ? .isButton : [])
            .accessibilityHint(turn.isQuotaLock ? "Opens Unlock Coach paywall" : "")
            if turn.kind != .user { Spacer(minLength: 36) }
        }
    }

    private func showsFeedback(for turn: CoachChatTurn) -> Bool {
        turn.kind == .assistant
            && !turn.isStreaming
            && !turn.isFailure
            && !turn.isQuotaLock
            && !turn.text.isEmpty
    }

    private func feedbackRow(for turn: CoachChatTurn) -> some View {
        HStack(spacing: 14) {
            Button {
                feedbackTarget = CoachFeedbackTarget(rating: .up, turn: turn)
            } label: {
                Image(systemName: "hand.thumbsup")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("Thumbs up")
            .accessibilityIdentifier("coach.feedback.up")

            Button {
                feedbackTarget = CoachFeedbackTarget(rating: .down, turn: turn)
            } label: {
                Image(systemName: "hand.thumbsdown")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("Thumbs down")
            .accessibilityIdentifier("coach.feedback.down")

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(
                AppLanguageStore.text("coach.placeholder", default: "Ask something sharp…"),
                text: $chat.draft,
                axis: .vertical
            )
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
                    .background(ember, in: Circle())
            }
            .accessibilityLabel(chat.isSending
                ? AppLanguageStore.text("coach.sending", default: "Sending")
                : AppLanguageStore.text("coach.send", default: "Send"))
            .disabled(chat.isSending || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, ScaleLayout.pageInset)
        .padding(.vertical, ScaleLayout.chromeInset)
    }
}

private struct CoachFeedbackTarget: Identifiable {
    var id: String { "\(turn.id.uuidString)-\(rating.rawValue)" }
    let rating: ScaleFeedbackRating
    let turn: CoachChatTurn
}

private struct StreamingCursor: View {
    var tint: Color = ScaleChrome.signal
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(tint)
            .frame(width: 10, height: 18)
            .opacity(on ? 1 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    on = false
                }
            }
    }
}
