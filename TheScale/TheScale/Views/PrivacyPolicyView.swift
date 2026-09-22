import SwiftUI

/// Full-screen reader for Privacy / Terms / Medical / US notice / Liability.
struct LegalDocumentView: View {
    let document: ScaleLegal.Document

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.42, green: 0.45, blue: 0.50)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(document.title)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(ink)
                    .accessibilityIdentifier("legal.documentTitle")

                Text(document.body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(ink.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("legal.documentBody")
            }
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
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if document == .privacyPolicy {
                    Link("Web", destination: ScaleLegal.privacyPolicyURL)
                } else if document == .termsOfUse {
                    Link("Web", destination: ScaleLegal.termsOfUseURL)
                }
            }
        }
    }
}

/// Back-compat wrapper used by older NavigationLinks.
struct PrivacyPolicyView: View {
    var body: some View {
        LegalDocumentView(document: .privacyPolicy)
    }
}

#Preview {
    NavigationStack {
        LegalDocumentView(document: .privacyPolicy)
    }
}
