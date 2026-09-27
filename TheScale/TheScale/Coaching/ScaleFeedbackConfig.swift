import Foundation

/// Public endpoints for consumer feedback (no secrets).
/// Resend + service-role keys live only in Supabase Edge Function secrets.
enum ScaleFeedbackConfig {
    /// Supabase project hosting `app_feedback` + `submit-feedback`.
    static let projectURL = URL(string: "https://qtopujfrhfdzcngomoel.supabase.co")!

    /// Edge Function that validates → inserts → emails `dev@humananalog.ai`.
    static let submitFunctionURL = projectURL
        .appendingPathComponent("functions/v1/submit-feedback")

    /// Anon (publishable) key — client→Edge Function auth only. Never service role.
    /// Override in `Secrets.xcconfig` as `SUPABASE_ANON_KEY` for local rotation without a rebuild wait.
    static var anonKey: String {
        if let override = string(forInfoKey: "SupabaseAnonKey"), !override.isEmpty {
            return override
        }
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF0b3B1amZyaGZkemNuZ29tb2VsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMzA3MjEsImV4cCI6MjEwNTgwNjcyMX0.4I0Klz984MM0N6QqvEKBl8DExsV1-5LSR7DgYYoI-8U"
    }

    static let maxMessageLength = 2000
    static let maxContactLength = 320
    static let feedbackInbox = "dev@humananalog.ai"

    private static func string(forInfoKey key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
