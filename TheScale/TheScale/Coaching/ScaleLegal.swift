import Foundation

/// Legal / App Store / GDPR / US privacy surfaces.
/// Keep medical disclaimer out of notifications and Coach chat bodies.
enum ScaleLegal {
    /// Public privacy policy for App Store Connect. Keep this URL live.
    static let privacyPolicyURL = URL(string: "https://humananalog.github.io/fatnag/privacy")!

    /// Public terms URL (mirror of in-app Terms).
    static let termsOfUseURL = URL(string: "https://humananalog.github.io/fatnag/terms")!

    /// Public support page for App Store Connect Support URL.
    static let supportURL = URL(string: "https://humananalog.github.io/fatnag/support")!

    /// Controller / seller of record.
    static let controllerName = "Human Analog Limited"

    /// Privacy / DSAR contact (also used for CCPA requests).
    static let privacyEmail = "privacy@humananalog.ai"
    static let privacyMailtoURL = URL(string: "mailto:privacy@humananalog.ai")!

    /// Minimum age (COPPA / GDPR child rules; app already gates 18+ for BIA).
    static let minimumAgeYears = 18

    /// Document catalog shown in Settings → Privacy & Legal.
    enum Document: String, CaseIterable, Identifiable, Sendable {
        case privacyPolicy
        case termsOfUse
        case medicalDisclaimer
        case subscriptionTerms
        case usStatePrivacy
        case liability

        var id: String { rawValue }

        var title: String {
            switch self {
            case .privacyPolicy: return "Privacy Policy"
            case .termsOfUse: return "Terms of Use"
            case .medicalDisclaimer: return "Medical & Fitness Disclaimer"
            case .subscriptionTerms: return "Subscriptions"
            case .usStatePrivacy: return "US State Privacy Notice"
            case .liability: return "Limitation of Liability"
            }
        }

        var body: String {
            switch self {
            case .privacyPolicy: return ScaleLegal.privacyPolicyBody
            case .termsOfUse: return ScaleLegal.termsOfUseBody
            case .medicalDisclaimer: return ScaleLegal.medicalDisclaimerBody
            case .subscriptionTerms: return ScaleLegal.subscriptionTermsBody
            case .usStatePrivacy: return ScaleLegal.usStatePrivacyBody
            case .liability: return ScaleLegal.liabilityBody
            }
        }
    }

    // MARK: - Privacy Policy (GDPR Art. 12-14 + US)

    static let privacyPolicyBody = """
    FATNAG Privacy Policy

    Controller: \(controllerName)
    App: FATNAG (iOS), bundle app.thescale.ios
    Effective: 22 September 2026
    Contact: \(privacyEmail)

    1. Who we are
    \(controllerName) (“we”, “us”) provides FATNAG. We are the data controller for personal data processed through the app when that data leaves your device to our systems (optional Keel Coach). Most weighing, Health, and profile data stays on your iPhone under your control.

    2. What we process
    A. On-device only (not sent to us unless you opt into Keel Coach):
    • Scale readings, calibration, body profile, diet / location / avoidances, weekly goals, meal plans, chart comments, Coach memory, personas, preferences, quotas.
    • Apple Health reads/writes you authorize (weight, body composition, heart, sleep, activity, nutrition, and related fitness signals used for charts and digests).
    • Local notifications you enable.

    B. Optional Keel Coach (only after explicit consent):
    • Chat text you send, short fitness digests, and profile persona lines needed for coaching.
    • Transmitted over HTTPS to our Cloudflare Worker, which may call xAI (Grok) to generate a reply.
    • We do not sell this data. We do not use it for advertising.

    C. Apple platforms:
    • App Store / StoreKit subscription status (handled by Apple).
    • Apple Intelligence / on-device Foundation Models when available (processed on device; not our servers).

    3. Purposes and legal bases (GDPR)
    • Provide core weighing, Health sync, charts, and local coaching: performance of a contract (GDPR Art. 6(1)(b)) and/or legitimate interests in running a fitness tool (Art. 6(1)(f)), balanced against your rights.
    • Special-category health-related data on device: processed under your explicit HealthKit permission and, where required, Art. 9(2)(a) consent and/or Art. 9(2)(h)/(i) as applicable for wellness self-management tools. FATNAG is not a medical device.
    • Optional Keel Coach network calls: consent (Art. 6(1)(a); Art. 9(2)(a) where health-context leaves the device). Withdraw anytime in Settings.
    • Subscriptions and fraud prevention: contract and legitimate interests; billing is via Apple.
    • Legal compliance and security: Art. 6(1)(c) and (f).

    4. Children
    FATNAG is for adults \(minimumAgeYears)+. We do not knowingly collect data from children. If you believe a minor used the app, contact \(privacyEmail); we will help delete on-device data instructions and revoke Coach consent.

    5. Sharing and processors
    • Apple (HealthKit, App Store, notifications framework) under Apple’s terms.
    • Cloudflare (edge Worker) and xAI (model inference) only when Keel Coach is consented.
    • No advertising networks. No sale or “share for cross-context behavioral advertising” of personal information.
    International transfers (EEA/UK → US processors) use appropriate safeguards (e.g. Standard Contractual Clauses and vendor measures). Ask \(privacyEmail) for transfer details.

    6. Retention
    • On-device data: until you delete it in Settings (Erase my data) or remove the app.
    • Keel Coach request logs on our Worker: kept only as needed for security, abuse prevention, and debugging, then deleted or aggregated. We do not build long-term dossiers.
    • Legal holds may extend retention when required by law.

    7. Your rights (EEA/UK/Switzerland)
    You may have rights to access, rectify, erase, restrict, portability, and object, and to withdraw consent without affecting prior lawful processing. Use in-app Export / Erase, or email \(privacyEmail). You may lodge a complaint with your local supervisory authority.

    8. US residents
    See the separate “US State Privacy Notice” in Settings for CCPA/CPRA and similar state laws (no sale/share; right to know, delete, correct, and limit use of sensitive personal information where applicable).

    9. Security
    Data on device uses iOS protections. Network Coach uses HTTPS. No method is perfectly secure; use a passcode / Face ID / Touch ID on your phone.

    10. Changes
    We may update this policy. Material changes will be reflected in-app and at \(privacyPolicyURL.absoluteString). Continued use after notice means you acknowledge the update. Coach consent can always be withdrawn.

    11. Contact
    \(controllerName)
    Privacy: \(privacyEmail)
    """

    // MARK: - Terms of Use

    static let termsOfUseBody = """
    FATNAG Terms of Use

    Provider: \(controllerName)
    Effective: 22 September 2026

    1. Agreement
    By downloading or using FATNAG you agree to these Terms, the Privacy Policy, the Medical & Fitness Disclaimer, and (if you subscribe) the Subscription Terms. If you do not agree, do not use the app.

    2. Eligibility
    You must be at least \(minimumAgeYears) years old and able to form a binding contract. The app is a consumer fitness tool, not a clinical service.

    3. License
    We grant you a personal, non-exclusive, non-transferable, revocable license to use FATNAG on Apple devices you own or control, subject to the App Store Terms and these Terms. You may not reverse engineer, scrape, abuse APIs, or use the app to harm others.

    4. Accounts and device storage
    Profile and history primarily live on your device. You are responsible for device access control and backups. Losing the device or deleting the app may erase local data.

    5. Optional Keel Coach
    Live Coach is optional, capped by your plan’s weekly credits, and requires privacy consent. Outputs are AI-generated suggestions, not professional advice. We may suspend Coach for abuse, security, or cost control.

    6. HealthKit and Bluetooth scales
    Health access is optional and managed in iOS Settings. Third-party scales (e.g. Mi Body Composition Scale 2) communicate over Bluetooth LE; we do not operate those manufacturers’ clouds for pairing in this app.

    7. Acceptable use
    No unlawful, harassing, or infringing use. No attempt to extract model weights, bypass quotas, or overload our Worker.

    8. Intellectual property
    FATNAG name, UI, and software are owned by \(controllerName) or licensors. Feedback you send may be used to improve the product without obligation to you.

    9. Disclaimer of warranties
    THE APP IS PROVIDED “AS IS” AND “AS AVAILABLE” WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT. We do not warrant uninterrupted or error-free operation, or accuracy of weight, body composition, or AI output.

    10. Limitation of liability
    See “Limitation of Liability” in Settings. To the maximum extent permitted by law, our aggregate liability arising from the app is limited as stated there.

    11. Indemnity
    You agree to defend and indemnify \(controllerName) and its officers, directors, and agents from claims arising from your misuse of the app, your violation of these Terms, or your violation of law, except to the extent caused by our willful misconduct.

    12. Governing law
    These Terms are governed by the laws of Hong Kong SAR, without regard to conflict-of-law rules, except that mandatory consumer protections in your country of residence (including EEA) still apply. Courts of Hong Kong have non-exclusive jurisdiction; EEA consumers may also bring proceedings in their place of residence.

    13. Changes and termination
    We may update Terms in-app. We may suspend or stop the service. You may stop using the app and erase local data anytime.

    14. Contact
    \(privacyEmail)
    """

    // MARK: - Medical

    static let medicalDisclaimerBody = """
    Medical & Fitness Disclaimer

    Provider: \(controllerName)
    Effective: 22 September 2026

    FATNAG and Keel Coach provide fitness, nutrition, and lifestyle information for educational and motivational purposes only.

    NOT MEDICAL CARE
    • Not a medical device, not FDA/CE clinical software, not a diagnosis or treatment service.
    • Body composition from consumer scales and impedance estimates can be inaccurate.
    • AI Coach replies can be wrong, incomplete, or inappropriate for your situation.

    SEEK PROFESSIONAL HELP
    • Talk to a qualified clinician before changing diet, fasting, exercise, or medication.
    • If you have chest pain, fainting, severe distress, disordered eating concerns, pregnancy, or other red-flag symptoms, seek emergency or clinical care. Do not rely on this app.

    NO CLINICIAN-PATIENT RELATIONSHIP
    Use of FATNAG does not create a doctor-patient, therapist-patient, or dietitian-client relationship with \(controllerName) or any model provider.

    ASSUMPTION OF RISK
    You assume the risks of using consumer weighing, Health data, fasting protocols, and training suggestions. Follow device and HealthKit permissions carefully.

    Short in-app reminder (onboarding / Legal card):
    \(CoachCopySanitize.medicalDisclaimer)
    """

    // MARK: - Subscriptions

    static let subscriptionTermsBody = """
    Subscription Terms (App Store)

    Provider: \(controllerName)
    Billing: Apple App Store / StoreKit
    Effective: 22 September 2026

    PLANS
    • Free: limited weekly live Keel credits; core weighing and local features.
    • Plus / Pro: auto-renewable monthly subscriptions unlocking higher weekly Keel credits. Product IDs: app.thescale.ios.plus.monthly and app.thescale.ios.pro.monthly.

    APPLE BILLING
    Payment is charged to your Apple ID. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period in your Apple ID subscription settings. Manage or cancel in iOS Settings → Apple ID → Subscriptions. Refunds are handled by Apple under Apple’s policies.

    TRIALS / OFFERS
    If an introductory offer is shown in the App Store or StoreKit sheet, Apple’s terms for that offer apply.

    CONTENT
    Subscriptions grant access to higher Coach quotas and related digital features, not physical goods. Features may change as we improve the product.

    PRIVACY
    Purchase receipts are processed by Apple. See Privacy Policy for Coach data handling after purchase.
    """

    // MARK: - US State Privacy (CCPA/CPRA etc.)

    static let usStatePrivacyBody = """
    US State Privacy Notice

    Controller: \(controllerName)
    Contact: \(privacyEmail)
    Effective: 22 September 2026

    This notice supplements the Privacy Policy for residents of California and other US states with similar laws (e.g. Virginia, Colorado, Connecticut, Utah, and others as applicable).

    CATEGORIES COLLECTED
    • Identifiers (e.g. on-device profile name you enter; Apple ID handled by Apple for purchases).
    • Health and fitness information (on device; optionally included in Keel digests you consent to send).
    • Customer content (Coach chat you send after consent).
    • Inferences related to fitness goals derived on device for coaching.
    We do not collect precise geolocation for advertising. City/area you type for meal context stays on device unless included in a consented Coach prompt.

    SALE / SHARE
    We do not sell personal information. We do not share personal information for cross-context behavioral advertising. We do not use sensitive personal information for purposes that require a “Limit the Use” right beyond providing the services you request.

    YOUR RIGHTS
    Subject to verification and exceptions, you may request: know/access, delete, correct, and portability; and appeal a denial where state law requires. Use in-app Export my data / Erase my data, or email \(privacyEmail). Authorized agents may contact us with proof of authority.

    METRICS
    We do not currently operate a US “Do Not Sell or Share” web form because we do not sell or share as defined above. Requests are handled by email and in-app tools.

    NON-DISCRIMINATION
    We will not discriminate against you for exercising privacy rights.
    """

    // MARK: - Liability

    static let liabilityBody = """
    Limitation of Liability

    Provider: \(controllerName)
    Effective: 22 September 2026

    TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW:

    1. \(controllerName) AND ITS SUPPLIERS ARE NOT LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR ANY LOSS OF DATA, PROFITS, GOODWILL, OR OTHER INTANGIBLE LOSSES, ARISING FROM YOUR USE OF FATNAG, HEALTHKIT, THIRD-PARTY SCALES, OR KEEL COACH.

    2. OUR TOTAL LIABILITY FOR ALL CLAIMS IN THE AGGREGATE SHALL NOT EXCEED THE GREATER OF (A) THE AMOUNTS YOU PAID US FOR THE APP SUBSCRIPTION IN THE TWELVE (12) MONTHS BEFORE THE CLAIM (EXCLUDING APPLE’S COMMISSION WHERE NOT RECEIVED BY US) OR (B) USD $50.

    3. THE ABOVE LIMITS DO NOT EXCLUDE LIABILITY THAT CANNOT BE EXCLUDED UNDER MANDATORY LAW (INCLUDING LIABILITY FOR DEATH OR PERSONAL INJURY CAUSED BY NEGLIGENCE WHERE SUCH LIMITATION IS PROHIBITED, OR FRAUD).

    4. EEA/UK CONSUMERS retain mandatory statutory rights. These limits apply only to the extent allowed in your jurisdiction.

    5. AI AND MEASUREMENT OUTPUTS are suggestions only. You are solely responsible for decisions about health, diet, and training.
    """

    /// Compact policy still used where a short paste is needed; full text is `privacyPolicyBody`.
    static var privacyPolicyShortSummary: String {
        "On-device first. Keel Coach is opt-in. No ads, no sale of data. Rights: export/erase in Settings or \(privacyEmail)."
    }

    static let appStoreReviewNotes = """
    FATNAG: App Review notes
    ASC app id: 6816630442 · bundle app.thescale.ios

    Hardware: Xiaomi Mi Body Composition Scale 2 via Bluetooth LE advertisements (no pairing cloud).
    HealthKit: write mass/BMI/fat%/lean on Confirm; read only types used for charts + fitness coaching digests.
    Background: healthkit observers + enableBackgroundDelivery for workouts/sleep/weight/steps/HR; BGAppRefresh + BGProcessing as backups for fitness checks. iOS may throttle.
    Network: optional Keel Coach via HTTPS Worker after explicit consent. Store builds should leave GROK_API_KEY empty (Worker holds XAI_API_KEY). App sends GROK_APP_SECRET (shared Worker secret via Secrets.xcconfig), never the xAI master key.
    Notifications: local UNUserNotificationCenter; Time Sensitive only for user-requested wake pings; Communication-style Coach chrome when entitlement allows.
    Medical: disclaimer in onboarding + Settings → Legal only; never in notification bodies.
    Privacy: GDPR/CCPA texts in Settings; in-app Export / Erase; Privacy Policy \(privacyPolicyURL.absoluteString); Terms \(termsOfUseURL.absoluteString); age gate \(minimumAgeYears)+.
    IAP: Plus \(ScaleStorefront.plusProductID) and Pro \(ScaleStorefront.proProductID) monthly under subscription group Coach. Restore Purchases on the paywall.
    No native Watch app in 1.0 (iPhone notifications may mirror). Live Activity during weigh-in only.
    """
}
