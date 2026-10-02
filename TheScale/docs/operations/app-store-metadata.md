# App Store Connect metadata stubs (1.0 consumer)

Fill these in ASC before Submit for Review. Binary alone is not enough.

## App record

| Field | Value |
|-------|--------|
| ASC Apple ID / app id | **6816630442** |
| Inflight iOS version | [App Store Connect · Inflight](https://appstoreconnect.apple.com/apps/6816630442/distribution/ios/version/inflight) |
| Name (listing) | **FATNAG** (accepted in ASC) |
| Subtitle (≤30) | **Nag until the fat folds.** (24 chars; primary) |
| Subtitle alternates | `Daily nag. Smaller pants.` · `Weigh. Nag. Lose. Repeat.` |
| Bundle ID | `app.thescale.ios` (unchanged) |
| SKU | `thescale-ios` (or your convention) |
| Primary language | English (U.S.) |
| Additional localizations | In-app language picker (onboarding step 1 + Settings). String Catalog covers App Store distribution locales; expand ASC locale listings as screenshots land. |
| Category | **Health & Fitness** |
| Secondary | Lifestyle (optional) |
| Seller | Human Analog Limited (`XHVW66YM39`) |

IAP product IDs (Coach group, App Store X.99):

- Plus Monthly: `app.thescale.ios.plus.monthly` — **$1.99**
- Plus Annual: `app.thescale.ios.plus.annual` — **$19.99**
- Pro Monthly: `app.thescale.ios.pro.monthly` — **$7.99**
- Pro Annual: `app.thescale.ios.pro.annual` — **$79.99**

## Inflight version form (paste checklist)

Use on the Inflight version page for **6816630442**:

| Field | Paste |
|-------|--------|
| **Name** | `FATNAG` |
| **Subtitle** (≤30) | `Nag until the fat folds.` |
| **Subtitle alternates** (if Alex overrides) | `Daily nag. Smaller pants.` / `Weigh. Nag. Lose. Repeat.` |
| **Promotional text** (updatable anytime) | `Nag until the fat folds — daily weigh-ins that keep the routine until the loss shows. Apple Health sync. Honest Coach credits.` |
| **Description opener** | `FATNAG nags you into the habit that shrinks the folds: weigh daily, stay honest, win the week. Privacy-first companion for compatible Bluetooth body scales — weigh-ins stay on your iPhone, confirm into Apple Health, and optional Keel Coach helps when you go soft, with weekly credit caps instead of endless chat spam.` |
| **Keywords** | `scale,weight,body fat,healthkit,fasting,coach,fitness,bia,weigh in,bluetooth` |
| **Support URL** | `https://humananalog.github.io/fatnag/support` |
| **Privacy Policy URL** | `https://humananalog.github.io/fatnag/privacy` |
| **Category** | Health & Fitness |

Full description body + review notes below.

## Age rating / content

- **Not a medical device.** Wellness / fitness only.
- Age gate in-app: **18+** (BIA / adult fitness).
- ASC Age Rating questionnaire: answer **Medical/Treatment Information** carefully - the app discusses fitness/nutrition coaching, **not** diagnosis or treatment. Prefer answers that reflect educational fitness content; avoid claiming clinical care.
- Unrestricted Web Access: No
- Gambling / Contests: No

## Privacy Policy URL (required)

Must be live HTTPS:

`https://humananalog.github.io/fatnag/privacy`

Hosting steps: `docs/operations/legal-url-hosting.md`. Public path is `humananalog.github.io/fatnag`; product name in HTML is **FATNAG**.

## App Privacy (nutrition labels)

Match `PrivacyInfo.xcprivacy` + in-app policy:

| Data type | Linked | Tracking | Purpose |
|-----------|--------|----------|---------|
| Health & Fitness | Yes (on-device profile / optional Coach) | No | App Functionality |
| Other User Content (Coach chat when consented; typed city/diet notes - **not** GPS) | Yes | No | App Functionality |
| Name (greeting name user types) | Yes | No | App Functionality |
| Purchases (StoreKit) | Yes (via Apple) | No | App Functionality |

No advertising data. No tracking domains. No third-party analytics SDKs.

## Screenshots (required stubs)

Capture on the latest required iPhone sizes in ASC (typically 6.7" + 6.1"):

1. **Home** - weekly goal / day gauges (no debug chrome).
2. **Live weigh-in** - Live scale sheet with settled weight.
3. **Progress / charts** - weight history with ideal line.
4. **Coach** - chat thread (consent already granted on the demo device).
5. **Paywall** - Free / Plus / Pro (luxury sheet).
6. Optional: **Settings → Privacy** showing Export / Erase.

Do **not** include DEBUG menus, plan overrides, or sample notification buttons.

## Promotional text / description (draft)

**Catchphrase note:** Primary subtitle **Nag until the fat folds.** is the funny FATNAG line — daily nagging that keeps the weigh-in routine until body fat actually folds/shrinks. Do **not** put a hardware brand in the subtitle or punch lines (supported scales belong only in description / Bluetooth setup copy).

**Promotional text (updatable):** Nag until the fat folds — daily weigh-ins that keep the routine until the loss shows. Apple Health sync. Honest Coach credits.

**Description (draft):**
FATNAG nags you into the habit that shrinks the folds: weigh daily, stay honest, win the week. Privacy-first companion for compatible Bluetooth body scales — weigh-ins stay on your iPhone, confirm into Apple Health, and optional Keel Coach helps when you go soft, with weekly credit caps instead of endless chat spam.

- Bluetooth LE read of compatible scale advertisements (no manufacturer cloud pairing)
- Body composition estimates + Apple Health write on Confirm
- Charts, trend, and dream-weight projection
- Local notifications for morning weigh drills and fitness signals you enable
- Optional live Coach after explicit consent (HTTPS Worker; no pasted API keys)

Not a medical device. Fitness guidance only.

## Keywords (draft)

`scale,weight,body fat,healthkit,fasting,coach,fitness,bia,weigh in,bluetooth`

## Support + marketing URLs

| Field | Value |
|-------|--------|
| Support URL | `https://humananalog.github.io/fatnag/support` (`ScaleLegal.supportURL`) |
| Marketing URL | Optional product page |
| Privacy | See above |

## HealthKit review notes (paste into ASC Review Notes)

Use / adapt `ScaleLegal.appStoreReviewNotes`:

```
FATNAG: App Review notes
ASC app id: 6816630442 · bundle app.thescale.ios

Hardware: compatible Bluetooth LE body scales via advertisements (no pairing cloud). Mi Body Composition Scale 2 (`0x181B`) is supported today; the decoder registry is brand/model agnostic for more scales.
HealthKit: write mass/BMI/fat%/lean on Confirm; read only types used for charts + fitness coaching digests.
Background: healthkit observers + enableBackgroundDelivery for workouts/sleep/weight/steps/HR; BGAppRefresh + BGProcessing as backups for fitness checks. iOS may throttle.
Network: optional Keel Coach via HTTPS Worker after explicit consent. Store builds leave GROK_API_KEY empty (Worker holds the secret).
Notifications: local UNUserNotificationCenter; Time Sensitive only for user-requested wake pings; Communication-style Coach chrome when entitlement allows.
Medical: disclaimer in onboarding + Settings → Legal only; never in notification bodies.
Privacy: GDPR/CCPA texts in Settings; in-app Export / Erase; Privacy Policy https://humananalog.github.io/fatnag/privacy; age gate 18+.
IAP: Plus monthly $1.99 / annual $19.99 (28 credits/wk); Pro monthly $7.99 / annual $79.99 (120 credits/wk). Product IDs under Coach group. Sandbox tester account provided separately.
```

## Demo account

No login account. Provide:

- Sandbox Apple ID for IAP restore/purchase
- Note that a Bluetooth scale is optional for review if Manual weigh-in + Health samples are present on the review device
- Steps: Onboard → allow Health → Manual weigh-in or Confirm from Health → open Coach after consent → Settings Export/Erase visible

## Related

- `docs/operations/storekit-humananalog.md`
- `docs/operations/app-id-entitlements.md`
- `docs/operations/legal-url-hosting.md`
- `docs/operations/apple-watch-entry.md` (Watch = post-1.0)
