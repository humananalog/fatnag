import Foundation
import Security

/// Explicit opt-in before any Health-derived numbers leave the device toward Grok.
enum GrokPrivacyConsent {
    private static let key = "thescale.grokPrivacyConsentAccepted"

    static var isAccepted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
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
