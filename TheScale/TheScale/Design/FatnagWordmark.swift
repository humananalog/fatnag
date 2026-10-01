import SwiftUI

/// Official fatnag wordmark: light “fat” + heavy “nag” (matches brand SVG).
struct FatnagWordmark: View {
    var size: CGFloat = 28
    var color: Color = .primary
    var tracking: CGFloat = -0.8

    var body: some View {
        HStack(spacing: 0) {
            Text("fat")
                .font(.system(size: size, weight: .light, design: .default))
            Text("nag")
                .font(.system(size: size, weight: .heavy, design: .default))
        }
        .foregroundStyle(color)
        .tracking(tracking)
        .accessibilityLabel("fatnag")
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
        FatnagBrand.wordmarkImage
            .resizable()
            .scaledToFit()
            .frame(height: 36)
            .foregroundStyle(.primary)
    }
    .padding()
}
