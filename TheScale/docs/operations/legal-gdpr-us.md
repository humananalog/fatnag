# Legal & GDPR / US privacy (The Scale)

## In-app

Settings → **Privacy & Legal**:

| Document | Purpose |
|----------|---------|
| Privacy Policy (EU GDPR) | Controller, bases, processors, retention, EEA rights |
| US State Privacy Notice | CCPA/CPRA-style categories, no sale/share, rights |
| Terms of Use | Contract, warranty disclaimer, indemnity, governing law |
| Medical & Fitness Disclaimer | Not a medical device / no clinician relationship |
| Subscriptions | Apple billing / cancel / renew |
| Limitation of Liability | Cap + mandatory-law carve-outs |

Rights tools:

- **Export my data** → JSON of on-device profile, prefs, Coach memory/chat
- **Erase my data** → wipe The Scale UserDefaults stores + return to onboarding (Health samples stay in Health app)
- Email **privacy@humananalog.ai**

Onboarding requires acceptance of Terms + Privacy + fitness disclaimer (`LegalAcceptanceStore` records timestamp). Age gate 18+.

Keel Coach remains **consent-gated** (`GrokPrivacyConsent`) with accepted-at timestamp.

## Host public mirrors (App Store Connect)

Publish the same bodies at:

- `https://humananalog.github.io/the-scale/privacy`
- `https://humananalog.github.io/the-scale/terms`

ASC Privacy Policy URL must stay live. Product Review notes reference these URLs (`ScaleLegal.appStoreReviewNotes`).

## Nutrition label / PrivacyInfo.xcprivacy

Declares optional collection (when Keel consented) of Health & Fitness, Other User Content, Name, Coarse Location, Purchases. Tracking = false. No tracking domains.

## Not legal advice

These templates protect the product posture for EU and US consumer apps. Have counsel review before major launches or if you add new processors, ads, or accounts.
