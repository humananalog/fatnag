import Foundation

/// Stable on-device anonymous id for feedback correlation. Never Apple ID / Account.
enum ScaleAnonymousIdentity {
    private static let key = "thescale.anonymousUserId"

    static var userId: UUID {
        if let raw = UserDefaults.standard.string(forKey: key),
           let existing = UUID(uuidString: raw) {
            return existing
        }
        let fresh = UUID()
        UserDefaults.standard.set(fresh.uuidString, forKey: key)
        return fresh
    }

    #if DEBUG
    static func debugReset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
    #endif
}
