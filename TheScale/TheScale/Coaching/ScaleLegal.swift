import Foundation

/// Legal / App Store surfaces. Keep medical disclaimer out of notifications and Coach chat.
enum ScaleLegal {
    /// Public privacy policy for App Store Connect. Host this markdown (or HTML) and keep the URL live.
    /// Update when you publish under your own domain.
    static let privacyPolicyURL = URL(string: "https://humananalog.github.io/the-scale/privacy")!

    /// In-app privacy policy body (also mirrored in `docs/privacy-policy.md`).
    static let privacyPolicyBody = """
    The Scale Privacy Policy

    Effective for The Scale iOS app (Human Analog Limited).

    What stays on your iPhone
    • Scale readings, calibration, profile, Coach memory, personas, and preferences are stored on-device (UserDefaults / local files).
    • Confirmed weigh-ins write weight, BMI, body fat %, and lean body mass to Apple Health when you tap Confirm. Manual entries are marked user-entered in Health.
    • Health reads (weight, fat %, HR, RHR, HRV, sleep, steps, energy, workouts, and related fitness signals) stay on-device for charts, digests, and local algorithms unless you opt into Coach.

    Optional Coach (Keel)
    • Off by default. After you allow Coach requests, chat text and a fitness digest may be sent to our Cloudflare Worker, which calls xAI. We do not sell this data.
    • You can revoke consent anytime in Settings. On-device Apple Intelligence (when available) can polish notifications and private digests without leaving the phone.

    Notifications
    • Local only. Used for Coach reminders, trend / mini-goal nudges, and Watch / sleep-HR signals you enable. No marketing spam.

    Tracking
    • No advertising identifier, no analytics SDKs, no cross-app tracking.

    Contact
    • Human Analog Limited: use your App Store seller contact / support email for privacy requests.

    This app is not a medical device. Coaching is fitness guidance only.
    """

    static let appStoreReviewNotes = """
    The Scale: App Review notes

    Hardware: Xiaomi Mi Body Composition Scale 2 via Bluetooth LE advertisements (no pairing cloud).
    HealthKit: write mass/BMI/fat%/lean on Confirm; read only types used for charts + fitness coaching digests.
    Background: healthkit observers + enableBackgroundDelivery for workouts/sleep/weight/steps/HR; BGAppRefresh + BGProcessing as backups for fitness checks. iOS may throttle.
    Network: optional Keel Coach via HTTPS Worker after explicit consent. Store builds should leave GROK_API_KEY empty (Worker holds the secret).
    Notifications: local UNUserNotificationCenter; Time Sensitive only for user-requested wake pings; Communication-style Coach chrome when entitlement allows.
    Medical: disclaimer in onboarding + Settings → Legal only; never in notification bodies.
    """
}
