import StoreKit
import SwiftUI

/// Lightweight enjoyment check. High scores open the system review sheet; low scores exit quietly.
struct AppReviewPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    var onFinished: (() -> Void)?

    @State private var selectedStars: Int = 0
    @State private var thanksLine: String?

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.42, green: 0.45, blue: 0.50)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Quick pulse")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(steel)
                .textCase(.uppercase)
                .tracking(0.6)

            Text("FATNAG")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(ink)

            Text("How’s it going so far? One tap. No account, no survey.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(steel)

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        selectedStars = star
                        handle(stars: star)
                    } label: {
                        Image(systemName: star <= selectedStars ? "star.fill" : "star")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(star <= selectedStars
                                ? Color(red: 0.85, green: 0.55, blue: 0.12)
                                : steel.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
            }
            .padding(.vertical, 4)

            if let thanksLine {
                Text(thanksLine)
                    .font(.footnote)
                    .foregroundStyle(steel)
                    .transition(.opacity)
            }

            Button("Not now") {
                ScaleAppReviewPrompt.markSoftDismissed()
                finish()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(steel)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 0.99),
                    Color(red: 0.92, green: 0.94, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .onAppear {
            ScaleAppReviewPrompt.markSoftPromptShown()
        }
    }

    private func handle(stars: Int) {
        if stars >= 4 {
            thanksLine = "Glad it’s landing. Opening the App Store rating sheet…"
            // Brief beat so the tap feels acknowledged before the system sheet.
            // Gate: at most one StoreKit requestReview per install.
            ScaleAppReviewPrompt.markAppStoreReviewRequested()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                requestReview()
                finish()
            }
        } else {
            ScaleAppReviewPrompt.markLowScoreOptOut()
            thanksLine = "Thanks for the honest take. We’ll keep sharpening."
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                finish()
            }
        }
    }

    private func finish() {
        onFinished?()
        dismiss()
    }
}

#Preview {
    AppReviewPromptView()
}
