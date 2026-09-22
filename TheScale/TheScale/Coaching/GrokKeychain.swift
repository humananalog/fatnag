import Foundation
import Security

/// Explicit opt-in before any Health-derived numbers leave the device toward Keel / xAI.
enum GrokPrivacyConsent {
    private static let key = "thescale.grokPrivacyConsentAccepted"
    private static let acceptedAtKey = "thescale.grokPrivacyConsentAcceptedAt"

    static var isAccepted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            if newValue {
                if UserDefaults.standard.object(forKey: acceptedAtKey) == nil {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: acceptedAtKey)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: acceptedAtKey)
            }
        }
    }

    /// When consent was last granted (GDPR accountability). Nil if not accepted.
    static var acceptedAt: Date? {
        guard isAccepted else { return nil }
        let t = UserDefaults.standard.double(forKey: acceptedAtKey)
        guard t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }
}

/// Clears legacy per-user Keychain keys from older app versions (2.0 / 2.1 paste-in-Settings).
enum GrokLegacyKeychain {
    private static let service = "app.thescale.ios.grok"
    private static let account = "xai-api-key"

    @discardableResult
    static func clearUserEnteredKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
