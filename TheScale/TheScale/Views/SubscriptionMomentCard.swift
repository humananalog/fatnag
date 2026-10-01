import SwiftUI

/// Thank-you for a new plan or an upgrade. Goodbye when a plan steps down.
struct SubscriptionMomentCard: View {
    @EnvironmentObject private var session: ScaleSessionViewModel

    var moment: SubscriptionMoment
    var onFeedback: () -> Void
    var onSettings: () -> Void
    var onClose: () -> Void

    private var universe: ScalePaletteUniverse {
        .resolve(sex: session.profile.sex)
    }

    private var gold: Color { universe.paywallGold }
    private var ink: Color { universe.paywallInk }
    private let ivory = Color(red: 0.97, green: 0.95, blue: 0.92)
    private let mist = Color(red: 0.72, green: 0.70, blue: 0.66)

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    FatnagWordmark(size: 18, color: moment.isThanks ? gold : ivory.opacity(0.88))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ivory)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(AppLanguageStore.text("common.close", default: "Close"))
                }

                Spacer(minLength: 28)

                Text(moment.eyebrow.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(moment.isThanks ? gold : mist)

                Text(moment.title)
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                    .foregroundStyle(ivory)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)

                Text(moment.message)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(ivory.opacity(0.92))
                    .lineSpacing(3)
                    .padding(.top, 16)
                    .fixedSize(horizontal: false, vertical: true)

                Text(moment.feedbackLine)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(moment.isThanks ? gold.opacity(0.95) : mist)
                    .lineSpacing(3)
                    .padding(.top, 18)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 28)

                VStack(spacing: 12) {
                    Button(action: onFeedback) {
                        Text(AppLanguageStore.text("subscription.feedback", default: "Send feedback"))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(moment.isThanks ? ink : ivory)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(moment.isThanks ? gold : ivory.opacity(0.12))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("subscription.feedback")

                    Button(action: onSettings) {
                        Text(AppLanguageStore.text("subscription.settings_feedback", default: "Feedback in Settings"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(ivory.opacity(0.92))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(ivory.opacity(0.28), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("subscription.settingsFeedback")

                    Button(action: onClose) {
                        Text(
                            moment.isThanks
                                ? AppLanguageStore.text("subscription.continue", default: "Continue")
                                : AppLanguageStore.text("common.close", default: "Close")
                        )
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(mist)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("subscription.close")
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier(moment.isThanks ? "subscription.thanks" : "subscription.farewell")
    }

    private var background: some View {
        ZStack {
            ink.ignoresSafeArea()
            if moment.isThanks {
                Circle()
                    .fill(gold.opacity(0.38))
                    .frame(width: 320, height: 320)
                    .blur(radius: 50)
                    .offset(x: -80, y: -220)
                Circle()
                    .fill(gold.opacity(0.16))
                    .frame(width: 240, height: 240)
                    .blur(radius: 40)
                    .offset(x: 120, y: 180)
            }
        }
    }
}
