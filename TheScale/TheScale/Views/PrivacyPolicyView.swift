import SwiftUI

/// Full privacy policy for Settings / App Review. Mirrors `docs/privacy-policy.md`.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text(ScaleLegal.privacyPolicyBody)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.96, blue: 0.98),
                    Color(red: 0.88, green: 0.91, blue: 0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Link("Open web", destination: ScaleLegal.privacyPolicyURL)
            }
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
