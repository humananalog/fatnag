import Foundation

/// Shared Grok transport for every install of this build.
/// Preferred: `GrokProxyURL` → Cloudflare Worker holds the xAI key.
/// Fallback: `GrokAPIKey` baked via Secrets.xcconfig (IPA-extractable).
/// Missing both → offline mock.
enum GrokSharedConfig {
    private static let proxyInfoKey = "GrokProxyURL"
    private static let apiKeyInfoKey = "GrokAPIKey"

    /// Public HTTPS proxy that injects the shared xAI key server-side.
    static var proxyURL: URL? {
        guard let raw = string(forInfoKey: proxyInfoKey),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https"
        else { return nil }
        return url
    }

    /// Build-time shared key from Secrets.xcconfig → Info.plist. Prefer proxyURL.
    static var bakedAPIKey: String? {
        string(forInfoKey: apiKeyInfoKey)
    }

    /// True when this build can attempt a live Grok call (proxy or baked key).
    static var isLiveConfigured: Bool {
        proxyURL != nil || bakedAPIKey != nil
    }

    /// Operator-facing status for Settings (no secret values).
    static var statusSummary: String {
        if proxyURL != nil {
            return "Shared proxy configured for all installs of this build."
        }
        if bakedAPIKey != nil {
            return "Shared build-time key present. Prefer the Worker proxy for distribution; a baked key can be extracted from the IPA."
        }
        return "No shared proxy/key in this build. Coach stays on offline mock until Secrets.xcconfig is set and you rebuild."
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
