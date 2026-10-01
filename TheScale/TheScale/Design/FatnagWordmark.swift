import SwiftUI

/// Official fatnag wordmark: light “fat” + heavy “nag” (matches brand SVG).
///
/// The brand stem is always English **except** the Settings language Easter egg
/// (`jokeFat`), which swaps only “fat” for the local body-fat word.
struct FatnagWordmark: View {
    var size: CGFloat = 28
    var color: Color = .primary
    var tracking: CGFloat = -0.8
    /// Settings-only: show the local word for body fat instead of the brand stem.
    var jokeFat: Bool = false
    /// Bump after a language change to pulse the fat stem once.
    var fatPulseTick: Int = 0

    @State private var fatScale: CGFloat = 1

    private var fatStem: String {
        jokeFat
            ? AppLanguageStore.text("settings.brand.fat", default: "fat")
            : "fat"
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: fatStem)
                .font(.system(size: size, weight: .light, design: .default))
                .scaleEffect(fatScale)
            Text(verbatim: "nag")
                .font(.system(size: size, weight: .heavy, design: .default))
        }
        .foregroundStyle(color)
        .tracking(tracking)
        .accessibilityLabel("fatnag")
        .onChange(of: fatPulseTick) { _, tick in
            guard tick > 0 else { return }
            pulseFatOnce()
        }
    }

    private func pulseFatOnce() {
        fatScale = 1
        withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
            fatScale = 1.28
        }
        withAnimation(.spring(response: 0.40, dampingFraction: 0.78).delay(0.18)) {
            fatScale = 1
        }
    }
}

/// Vector asset for places that need `Image` (template-tinted).
enum FatnagBrand {
    static let displayName = "fatnag"
    /// Always the persisted app language (or system on first launch).
    static var tagline: String { AppLanguageStore.splashTagline }

    static var wordmarkImage: Image {
        Image("FatnagWordmark")
    }
}

#Preview {
    VStack(spacing: 24) {
        FatnagWordmark(size: 48, color: .white)
            .padding()
            .background(Color.black)
        FatnagWordmark(size: 28, color: .primary)
        FatnagWordmark(size: 28, color: .primary, jokeFat: true)
        FatnagBrand.wordmarkImage
            .resizable()
            .scaledToFit()
            .frame(height: 36)
            .foregroundStyle(.primary)
    }
    .padding()
}
