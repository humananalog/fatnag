import Foundation

/// Shared Grok transport for every install of this build.
/// Preferred: `GrokProxyURL` → Cloudflare Worker holds the xAI key; app sends `GrokAppSecret`.
/// Fallback: `GrokAPIKey` baked via Secrets.xcconfig (IPA-extractable; avoid for App Store).
/// Missing proxy+secret (or baked key) → offline mock. Fail closed without app secret.
enum GrokSharedConfig {
    private static let proxyInfoKey = "GrokProxyURL"
    private static let apiKeyInfoKey = "GrokAPIKey"
    private static let appSecretInfoKey = "GrokAppSecret"

    /// Why live coaching cannot start (nil when OK or intentionally offline).
    enum ConfigurationIssue: Equatable, Sendable {
        case missingProxyAndKey
        /// Proxy URL present but shared app↔Worker secret missing (fail closed).
        case missingAppSecret
        /// xcconfig `//` comment stripped `https://…` down to `https:` (or similar garbage).
        case malformedProxyURL(String)
        case nonHTTPSProxy

        var userMessage: String {
            switch self {
            case .missingProxyAndKey:
                return "Offline mock: this build has no shared Keel proxy/key. Ask the operator to set GROK_PROXY_URL in TheScale.xcconfig (escaped as https:/$()/…) and rebuild."
            case .missingAppSecret:
                return "Offline mock: Keel proxy URL is set but GROK_APP_SECRET is empty. Copy Secrets.example.xcconfig → Secrets.xcconfig, set the same value as the Worker APP_SHARED_SECRET, and rebuild."
            case .malformedProxyURL(let raw):
                return "Keel proxy URL is broken (\(raw)). Almost certainly xcconfig stripped https:// as a comment. Rebuild with GROK_PROXY_URL = https:/$()/the-scale-grok.alexhuther.workers.dev"
            case .nonHTTPSProxy:
                return "Keel proxy must be https. Check GROK_PROXY_URL in TheScale.xcconfig."
            }
        }
    }

    /// Raw Info.plist string before validation (for diagnostics; never a secret).
    static var rawProxyString: String? {
        string(forInfoKey: proxyInfoKey)
    }

    /// Public HTTPS proxy that injects the shared xAI key server-side.
    static var proxyURL: URL? {
        guard case .ok(let url) = proxyResolution else { return nil }
        return url
    }

    /// App ↔ Worker shared secret (not the xAI master key). From Secrets.xcconfig → Info.plist.
    static var appSecret: String? {
        string(forInfoKey: appSecretInfoKey)
    }

    /// Build-time shared key from TheScale.xcconfig → Info.plist. Prefer proxyURL.
    static var bakedAPIKey: String? {
        string(forInfoKey: apiKeyInfoKey)
    }

    /// True when this build can attempt a live Grok call (authenticated proxy or baked key).
    static var isLiveConfigured: Bool {
        if proxyURL != nil { return appSecret != nil }
        return bakedAPIKey != nil
    }

    /// Non-nil when live config is missing or the baked proxy string is garbage.
    static var configurationIssue: ConfigurationIssue? {
        if proxyURL != nil {
            if appSecret != nil { return nil }
            // Fail closed: proxy without shared secret must not call the Worker.
            return .missingAppSecret
        }
        if bakedAPIKey != nil { return nil }
        if let raw = rawProxyString {
            return diagnoseProxy(raw)
        }
        return .missingProxyAndKey
    }

    /// Operator-facing status for Settings (no secret values).
    static var statusSummary: String {
        if let issue = configurationIssue {
            switch issue {
            case .missingProxyAndKey:
                return "No shared proxy/key in this build. Coach stays on offline mock until TheScale.xcconfig has GROK_PROXY_URL (https:/$()/…) and you rebuild."
            case .missingAppSecret:
                return "Proxy URL set, but GROK_APP_SECRET missing. Add it via Secrets.xcconfig (gitignored) to match Worker APP_SHARED_SECRET, then rebuild."
            case .malformedProxyURL, .nonHTTPSProxy:
                return issue.userMessage
            }
        }
        if proxyURL != nil, appSecret != nil {
            return "Shared proxy + app secret configured for all installs of this build."
        }
        if bakedAPIKey != nil {
            return "Shared build-time key present. Prefer the Worker proxy for distribution; a baked key can be extracted from the IPA."
        }
        return "No shared proxy/key in this build. Coach stays on offline mock until TheScale.xcconfig has GROK_PROXY_URL and you rebuild."
    }

    private enum ProxyResolution {
        case ok(URL)
        case issue(ConfigurationIssue)
        case absent
    }

    private static var proxyResolution: ProxyResolution {
        guard let raw = rawProxyString else { return .absent }
        if let issue = diagnoseProxy(raw) {
            return .issue(issue)
        }
        guard let url = URL(string: raw) else {
            return .issue(.malformedProxyURL(raw))
        }
        return .ok(url)
    }

    /// Returns an issue when the string is not a usable https URL with a real host.
    private static func diagnoseProxy(_ raw: String) -> ConfigurationIssue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Classic xcconfig footgun: https://host → https:  (rest commented out)
        let lower = trimmed.lowercased()
        if lower == "https:" || lower == "http:" || lower.hasPrefix("https:localhost")
            || lower == "https:/" || lower == "http:/"
        {
            return .malformedProxyURL(trimmed)
        }

        guard let url = URL(string: trimmed) else {
            return .malformedProxyURL(trimmed)
        }
        guard let scheme = url.scheme?.lowercased() else {
            return .malformedProxyURL(trimmed)
        }
        if scheme != "https" {
            return .nonHTTPSProxy
        }
        let host = (url.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty || host == "localhost" {
            return .malformedProxyURL(trimmed)
        }
        return nil
    }

    private static func string(forInfoKey key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        // Unexpanded build setting leftover
        if trimmed.hasPrefix("$(") { return nil }
        return trimmed
    }
}
