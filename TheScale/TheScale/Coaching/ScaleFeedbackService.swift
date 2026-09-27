import Foundation
import UIKit

enum ScaleFeedbackCategory: String, CaseIterable, Identifiable, Sendable {
    case bug
    case idea
    case praise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: return "Bug"
        case .idea: return "Idea"
        case .praise: return "Praise"
        }
    }

    var subtitle: String {
        switch self {
        case .bug: return "Something broke or felt wrong"
        case .idea: return "A wish or improvement"
        case .praise: return "What’s working"
        }
    }

    var systemImage: String {
        switch self {
        case .bug: return "ladybug"
        case .idea: return "lightbulb"
        case .praise: return "heart"
        }
    }
}

enum ScaleFeedbackSource: String, Sendable {
    case settings
    case softAsk = "soft_ask"
    case debug
}

struct ScaleFeedbackPayload: Sendable {
    var category: ScaleFeedbackCategory
    var message: String
    var contact: String?
    var source: ScaleFeedbackSource
    var planTier: String
}

enum ScaleFeedbackError: LocalizedError, Sendable {
    case emptyMessage
    case messageTooLong
    case offline
    case server(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Add a short note before sending."
        case .messageTooLong:
            return "Keep it under \(ScaleFeedbackConfig.maxMessageLength) characters."
        case .offline:
            return "You’re offline. Try again when you’re back online."
        case .server(let detail):
            return detail
        case .notConfigured:
            return "Feedback isn’t configured in this build yet."
        }
    }
}

/// POSTs to Supabase Edge Function `submit-feedback` (insert + Resend server-side).
enum ScaleFeedbackService {
    @MainActor
    static func submit(_ payload: ScaleFeedbackPayload) async throws {
        let message = payload.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw ScaleFeedbackError.emptyMessage }
        guard message.count <= ScaleFeedbackConfig.maxMessageLength else {
            throw ScaleFeedbackError.messageTooLong
        }

        let contact = payload.contact?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(ScaleFeedbackConfig.maxContactLength)
        let contactValue = (contact?.isEmpty == false) ? String(contact!) : nil

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        let locale = Locale.current.identifier
        let device = UIDevice.current.model

        var body: [String: Any] = [
            "category": payload.category.rawValue,
            "message": message,
            "platform": "ios",
            "locale": locale,
            "device_model": device,
            "plan_tier": payload.planTier,
            "anonymous_user_id": ScaleAnonymousIdentity.userId.uuidString,
            "source": payload.source.rawValue
        ]
        if let version { body["app_version"] = version }
        if let build { body["build"] = build }
        if let contactValue { body["contact"] = contactValue }

        var request = URLRequest(url: ScaleFeedbackConfig.submitFunctionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(ScaleFeedbackConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(ScaleFeedbackConfig.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ScaleFeedbackError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw ScaleFeedbackError.server("Unexpected response.")
        }
        if (200...299).contains(http.statusCode) {
            ScaleFeedbackPrompt.markSubmitted()
            return
        }

        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? String {
            throw ScaleFeedbackError.server(humanize(serverError: err))
        }
        throw ScaleFeedbackError.server("Couldn’t send feedback (\(http.statusCode)). Try again shortly.")
    }

    private static func humanize(serverError: String) -> String {
        switch serverError {
        case "invalid_message": return "Add a short note before sending."
        case "invalid_category": return "Pick Bug, Idea, or Praise."
        case "insert_failed", "server_misconfigured":
            return "Server hiccup. Your note wasn’t saved — try again in a minute."
        default:
            return "Couldn’t send feedback. Try again shortly."
        }
    }
}

/// Soft post–happy-moment ask cadence (separate from App Store review).
@MainActor
enum ScaleFeedbackPrompt {
    private static let lastSoftAskKey = "thescale.feedback.lastSoftAskAt"
    private static let lastSubmitKey = "thescale.feedback.lastSubmitAt"
    private static let softAskCooldownDays: Double = 45
    private static let postSubmitCooldownDays: Double = 90

    static func markSubmitted(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: lastSubmitKey)
    }

    static func markSoftAskShown(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: lastSoftAskKey)
    }

    /// After a clearly good weigh-in (encourage / winner), optionally surface a soft ask.
    static func shouldOfferSoftAsk(now: Date = Date()) -> Bool {
        if let submitted = UserDefaults.standard.object(forKey: lastSubmitKey) as? Date {
            if now.timeIntervalSince(submitted) < postSubmitCooldownDays * 86_400 { return false }
        }
        if let last = UserDefaults.standard.object(forKey: lastSoftAskKey) as? Date {
            if now.timeIntervalSince(last) < softAskCooldownDays * 86_400 { return false }
        }
        // Prefer users who have real usage (same signal as review, but lower bar).
        return ScaleAppReviewPrompt.successfulWeighIns >= 2
    }

    #if DEBUG
    static func debugReset() {
        UserDefaults.standard.removeObject(forKey: lastSoftAskKey)
        UserDefaults.standard.removeObject(forKey: lastSubmitKey)
    }
    #endif
}
