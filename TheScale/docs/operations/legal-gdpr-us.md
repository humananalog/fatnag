# Legal & GDPR / US privacy (FATNAG)

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
- **Erase my data** → wipe FATNAG UserDefaults stores + return to onboarding (Health samples stay in Health app)
- Email **privacy@humananalog.ai**

Onboarding requires acceptance of Terms + Privacy + fitness disclaimer (`LegalAcceptanceStore` records timestamp). Age gate 18+.

Keel Coach remains **consent-gated** (`GrokPrivacyConsent`) with accepted-at timestamp.

## Host public mirrors (App Store Connect)

Publish the same bodies at:

- `https://humananalog.github.io/the-scale/privacy`
- `https://humananalog.github.io/the-scale/terms`

**Exact steps:** `docs/operations/legal-url-hosting.md` (HTML stubs under `/docs/legal-site/`). Do not invent live URLs — Pages (or equivalent) must actually deploy first.

ASC Privacy Policy URL must stay live. Product Review notes reference these URLs (`ScaleLegal.appStoreReviewNotes`).

Settings exposes both **in-app** documents and **web** links (Privacy + Terms). Until hosting is live, reviewers use in-app text.

## Nutrition label / PrivacyInfo.xcprivacy

Declares Health & Fitness, Other User Content (includes typed city/diet notes — **not** GPS / Core Location), Name, Purchases. Tracking = false. No tracking domains. Required-reason APIs: UserDefaults `CA92.1`, File Timestamp `C617.1`.

## Not legal advice

These templates protect the product posture for EU and US consumer apps. Have counsel review before major launches or if you add new processors, ads, or accounts.
