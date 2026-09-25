# App ID portal entitlements (Alex / Apple Developer)

The Xcode entitlements file already requests these capabilities. **Archive will fail or strip capabilities** until the App ID in the Developer portal matches.

## Bundle ID

`app.thescale.ios` — team **Human Analog Limited** (`XHVW66YM39`)

## Entitlements already in the project

File: `TheScale/Resources/TheScale.entitlements`

| Entitlement | Purpose |
|-------------|---------|
| HealthKit | Read/write Health samples |
| HealthKit background delivery | Observer-driven fitness checks |
| **Time Sensitive Notifications** | Coach wake / time-sensitive local alerts |
| **Communication Notifications** | Coach-style notification chrome |

## One-time portal steps

1. Sign in to [Apple Developer](https://developer.apple.com/account) as Human Analog.
2. Certificates, Identifiers & Profiles → **Identifiers** → App IDs → `app.thescale.ios`.
3. Enable:
   - HealthKit
   - **Time Sensitive Notifications**
   - **Communication Notifications** (under Notifications)
4. Save.
5. Regenerate / refresh the App Store provisioning profile used for Archive (Xcode → Settings → Accounts → Download Manual Profiles, or let Xcode manage signing).
6. Clean + Archive. Confirm the signed IPA still contains Time Sensitive + Communication entitlements (`codesign -d --entitlements :-`).

## Ops note

Do this **before** the first App Store / TestFlight archive that uses Time Sensitive. Entitlements in the repo alone are not enough.

## Related

- Notification design notes: `/docs/health-and-notifications.md` (repo root)
- Review copy: `ScaleLegal.appStoreReviewNotes`
