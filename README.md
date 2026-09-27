# The Scale

Privacy-first iOS app for the **Xiaomi Mi Body Composition Scale 2** (XMTZC05HM; label variant XMTZCOSHM treated the same). Replaces Zapp Lite: BLE weigh-ins on-device only, results into **Apple Health**, optional **Coach** via a shared Grok Worker, on-device **Apple Intelligence** when eligible, and a **0.5B Metal polish sidecar** on other compatible iPhones.

| | |
|------|--|
| **Version** | 2.52.4 (build 99) |
| **Device** | iPhone 15 (physical; BLE + HealthKit) |
| **Xcode / SDK** | Xcode 27, iOS 27 SDK |
| **Deployment** | iOS 26.0, iPhone only |
| **Bundle id** | `app.thescale.ios` |
| **Team** | Human Analog Limited (`XHVW66YM39`) |

No accounts. No analytics. Weigh-ins never leave the phone except into Apple Health. Users never paste an API key.

### App Store release checklist (2.47.0+)
- Privacy Manifest `PrivacyInfo.xcprivacy` ships in the app bundle (no GPS / no tracking)
- In-app Privacy + Terms + Export/Erase (Settings); host public mirrors per `TheScale/docs/operations/legal-url-hosting.md`
- App Store metadata stubs: `TheScale/docs/operations/app-store-metadata.md`
- StoreKit / sandbox: `TheScale/docs/operations/storekit-humananalog.md` + `Config/Products.storekit`
- `ITSAppUsesNonExemptEncryption = false` (HTTPS only)
- Dev tools menu is **DEBUG-only** (stripped from Release / App Store)
- Enable **Time Sensitive** + **Communication Notifications** on the App ID before Archive (`TheScale/docs/operations/app-id-entitlements.md`)
- Leave `GROK_API_KEY` empty for store IPAs; Worker holds `XAI_API_KEY`
- Watch app / home-screen widgets = **post-1.0**; Live Activities during weigh-in are shippable
- Review notes: see `ScaleLegal.appStoreReviewNotes`

---

## Features

### BLE weigh-in
- Scans Mi Scale ads (`MIBFS` / service data `0x181B`)
- Full-screen live sheet: weight dominant, fat % / lean %, trend color, edit-before-save
- On-device BIA estimates (fat, water, muscle, bone, BMI, visceral index)
- Trend vs last Health weight: green loss, yellow stable (±0.2 kg), red gain
- **Confirm to Health** writes weight, BMI, body fat %, lean body mass

### Calibration
- Settings → reference mass → same live sheet → store factor/offset on-device
- Does not write to Health

### History / charts / Trend / projection
- Charts from Apple Health `bodyMass` + `bodyFatPercentage` (ranges 1W-1Y; default 2W)
- Ideal line from Settings; Y domain never clips real samples
- X domain always spans the selected range (fixes sparse 3M/1Y + scroll frame spam)
- **Trend** toggle: OLS on last 14 days, projects to ideal with safe kg/wk caps
- Tap a point for its value

### Manual entry
- Mass/kg only (travel); optional timestamp; `HKMetadataKeyWasUserEntered`
- Opens History after save

### Coach (Grok)
- One user-facing Coach voice; streaming SSE via shared Worker
- Opt-in consent only (**Allow Grok coach requests**)
- Persona + on-device memory inject into prompts
- Target statements update profile after medical feasibility gates
- Offline witty fallbacks when intentionally unconfigured; broken proxy URLs surface a clear error

### Memory / persona
- Name, diet, location/ethnicity/language/vibe: `UserDefaults`
- Chat habit facts on-device; optional Foundation Models extract pass

### Health monitoring
- Fitness digest from HealthKit: HR, RHR, **HRV (SDNN)**, respiratory rate, wrist temperature, SpO2, VO2 max, sleep (+ stages / consistency when available), steps, energy, Exercise Time, workouts + distance
- Coach chat refreshes a **dated** digest on every ask (never invents missing metrics)
- Local algorithms: safe weight-rate caps (~0.5–1%/wk), pre-sleep HR (+ HRV), Watch-not-worn (HR vs steps/distance), transparent recovery/load band
- Optional automated Grok checks on interval (best-effort `BGAppRefresh`)
- Settings shows Health status + Allow Health access / Open Health

### Foundation Models notifications
- When Apple Intelligence is available: polish titles/bodies, judge weak pings
- Algorithmic triggers stay the gate; FM off → algorithmic copy
- Settings shows Apple Intelligence status; Coach chrome shows `FM ready` / `FM off`
- **2.9.0 SOTA local UX:** title/subtitle/body, categories + actions, threads, Communication-style Coach when fit, PNG visuals, App Intents deep links, intentional foreground presentation
- **HealthKit background:** `HKObserverQuery` + `enableBackgroundDelivery` (+ BG refresh/processing backups) so digest/trigger notifications can land without opening the app (iOS still throttles)

### Progress / goals
- **Paywall + Settings polish (2.14.1):** Unlock Coach one-pager (high contrast Free/Plus/Pro); meal cards match sheet background; Settings Done dismisses keyboard; Settings regrouped (You / Weekly AI / Coach / Alerts / Scale / Legal).
- **AI usage / meals / units (2.14.0):** Settings shows weekly online AI % + used/limit with Upgrade; meal carousel peeks + page dots + color; quota-exhausted menus via Foundation Models or solid metric-portion templates; preferred metric/imperial units across Settings, live weigh-in, meal plan, and Coach prompts.
- **Home day coach (2.13.0):** Today-ahead advice (local clock), macro-goal ETA vs planned date, passive BLE auto-open live card (no Find Scale primary), 10s auto-confirm, weigh-in analysis card (congratulate / reward / punish). Meal plan respects IF 16-8 + time of day; retro snake spinner while generating. Chart point comments (256 chars, on-device, last 30 days). Flat home (cards only for meal carousel).
- **Swift 6 concurrency + meal carousel frame (2.52.4):** Meal plan carousel clamps GeometryReader sizes (no negative/non-finite frames). On-device polish eligibility uses `utsname` only (no MainActor `UIDevice`). `ScaleDebugLog` and Foundation Models runtime gate use `@unchecked Sendable` lock boxes for Swift 6.
- **Alerts layout (2.52.3):** Notification Center and Settings Notifications use clear Permission / Coming up / Recent / Developer sections.
- **Simulator FM quiet fallback (2.52.2):** Simulator skips Apple Intelligence (avoids `promptTemplateNotFound` spam). Device host failures trip a process-lifetime breaker and fall back to algorithmic / Metal polish copy.
- **Imperial mass normalization (2.52.1):** History charts, manual weigh-in, onboarding memory, Settings clamp toast, trend subtitles, weekly status lines, Monday card copy, and notification samples honor preferred metric/imperial units via `UnitFormat`.
- **Female coach voice + visual plates (2.52.0):** Female insights nurture and praise; energy/protein shown as palm/fist/handful pictures (not bare kcal). Grok, on-device FM, and Metal polish share sex-tuned voice rules. Imperial display continues via UnitFormat.
- **On-device polish sidecar (2.51.0):** Metal 0.5B polish pack for iPhones without Apple Intelligence; AI-capable phones skip install. Package: `Packages/ScaleOnDevicePolish`.
- **Progress Monday weight (2.50.4):** Progress WEEK START / % / Sunday target use **last Monday** body mass from Health (prefer Monday morning 04:00-12:00; else any Monday sample; else last weigh before Tuesday). Persisted `weekStartKg` / `weekStartDate` realign when they do not match. Anchor date is always local Monday 00:00, never today, dream weight, or first mid-week weigh.
- **Monday week-start lock (2.50.2):** Settings/Debug Monday card preview is ephemeral — no rewrite of week-start kg / Sunday target / progress %. Removed mid-week >2.5 kg baseline wipe.
- **Analog dream scale pivot (2.50.1):** fixed reading marker at 12 o’clock; dial disc rotates about its true center so the chosen kg sits under the needle (Settings + onboarding).
- **Morning weigh 💩 drill (2.50.0):** fallback **06:30** local (migrates legacy 07:30); window closes **08:00**; skip if already weighed today; Keel title `Keel · 💩 drill` / body `Go drop a 💩 and use The Scale after!`; Time Sensitive unchanged. Loss delta shows clear minus (`-650g`) + "You're a winner" on hero, home, Progress, History.
- **ProgressView / console quiet (2.49.1):** re-audit — still zero determinate `ProgressView(value:total:)`; Settings/Paywall stay on `ScaleBoundedProgress`; Progress ACTION gauge remains custom. Home-gauge success logs stay silent; DEBUG FitnessDigest / Coach digest / soft-fail prints throttled via `ScaleDebugLog` (45s) so observer wakes cannot flood Console. Regression script `scripts/assert_no_determinate_progressview.py`.
- **Progress sheet ACTION polish (2.49.0):** amplified entrance punches (hero % / week-start / Sunday / chunky gauge); week-start + Sunday target as first-class hero numbers; roast body ~23pt with night ink contrast; sub-1 kg deltas/values render as `650g` (metric) or oz (imperial) via `UnitFormat`. Opacity floor + always-arm entrance preserved. Reduce Motion stays calm.
- **Black-screen launch fix (2.48.1):** atmosphere moved to `.background` with solid base fill (LaunchBackground never shows through as dead void); night ink contrast hardened; Progress entrance always arms (no opacity-0 chrome on void); splash 3.5s failsafe; `WeeklyGoalAtmosphere.safeFallback`.
- **Gender palette universes (2.48.0):** male **Glacier Forge** (cool graphite + teal-cyan haze) vs female **Bloom Copper** (rose-quartz + champagne-copper haze). Driven by profile sex; live switch in Settings. Default when sex missing: Glacier Forge. Tokens in `Design/ScalePaletteUniverse.swift`; applied to home/Progress haze + Coach/paywall chrome continuity.
- **Home weekly-goal hero (2.12.2+):** one composition (no home cards) with % + track haze, energy-balance advice, Meals carousel (Grok, day-keyed cache), daily targets. Coach chat type bumped. Tap % for Progress.
- Weekly mini-goal (Δ kg), progress bar, offline or live Grok roast
- **Monday morning card (2.8.0+ / 2.50.4):** after Confirm-to-Health (or Manual) on Monday local morning (04:00-12:00), full-screen week plan: last-week Δ, Sunday kg target paced to ideal + optional goal date, meals, Grok diagnostic. Cached per ISO week; regenerates on a new Monday weigh-in. Progress week-start = **last Monday Health weight** (see 2.50.4). Dev preview: Settings → Legal → **Dev** (ephemeral UI only — does **not** rewrite week-start / progress).
- Bad-trend alerts, Monday mini-goal, Coach wake reminders (Settings toggles)
- Dev sample SOTA ping: Settings → Legal → **Dev** → Fire sample SOTA notification

---

## Architecture

```
Mi Scale 2 (BLE ads)
        │
        ▼
   The Scale (iPhone)
        │
        ├── HealthKit  ←→  Apple Health
        ├── UserDefaults (profile, cal, memory, prefs)
        ├── Foundation Models (on-device; Apple Intelligence)
        │
        └── HTTPS (opt-in Coach / fitness)
                │
                ▼
        Cloudflare Worker (grok-proxy)
                │
                ▼
              xAI Grok
```

Depth: [docs/architecture.md](docs/architecture.md) · [docs/coach-and-ai.md](docs/coach-and-ai.md) · [docs/health-and-notifications.md](docs/health-and-notifications.md)

---

## Setup

### Mac Mini checkout

```bash
cd /Users/alexclaw/Projects/project-zero
git checkout main && git pull origin main
open TheScale/TheScale.xcodeproj
```

Standing rule: **Xcode 27 + latest iOS**. Point CLI tools at Xcode if needed:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Shared Grok proxy

Preferred: key stays on the Worker (never in the IPA).

```bash
cd workers/grok-proxy
npx wrangler secret put XAI_API_KEY   # paste at prompt; never commit
npx wrangler deploy
```

Canonical build config: `TheScale/Config/TheScale.xcconfig` (Debug + Release).

**xcconfig `https://` footgun:** Xcode treats `//` as a comment. Never write a bare `https://` URL.

```
# WRONG → becomes https:
GROK_PROXY_URL = https://the-scale-grok.the-scale-grok.workers.dev

# RIGHT (empty $() splice)
GROK_PROXY_URL = https:/$()/the-scale-grok.the-scale-grok.workers.dev
GROK_API_KEY =
```

Optional gitignored override: copy `Secrets.example.xcconfig` → `Secrets.xcconfig`. Prefer Worker over baking `GROK_API_KEY` into the IPA.

Health check: `curl -s https://the-scale-grok.the-scale-grok.workers.dev` → `{"ok":true,...,"stream":true}`

### Apple Intelligence + on-device polish sidecar (2.51.0)

1. **Apple Intelligence phones** (15 Pro / 16+): Settings → Apple Intelligence & Siri → on; wait for model. App Settings shows FM ready. Sidecar is **never** downloaded.
2. **Other compatible iPhones** (including base iPhone 15): after onboarding, auto-install **Qwen2.5 0.5B** (~470 MB, Wi-Fi preferred) via `Packages/ScaleOnDevicePolish`. Settings shows download / Polish ready.
3. Trigger a bad-trend alert or Coach wake reminder; copy should use your name and Coach voice (FM or sidecar).
4. If neither path is ready, algorithmic strings still fire.

### Run on iPhone 15 (required for BLE)

Simulator does **not** replace on-device BLE + HealthKit verification.

1. Open `TheScale/TheScale.xcodeproj`
2. Signing: team Human Analog Limited, bundle `app.thescale.ios`
3. Destination: **iPhone 15** → Product → Run
4. Allow Bluetooth; allow Health on first Confirm / Manual save

Unit tests (math only; not a BLE substitute):

```bash
cd TheScale
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -scheme TheScale -destination 'platform=iOS Simulator,name=iPhone 17'
```

Smoke-build without a phone:

```bash
cd TheScale
xcodebuild build -scheme TheScale -sdk iphoneos -configuration Debug -destination 'generic/platform=iOS'
```

---

## Privacy model

| Data | Where |
|------|--------|
| Scale weight / impedance | In memory on iPhone |
| Profile, persona, calibration, Coach memory, prefs | `UserDefaults` on device |
| Health reads / writes | HealthKit on device |
| Foundation Models | On-device only |
| Grok requests | Opt-in; short digest + memory → Worker (or build-time key) |
| Network | None by default |

**HealthKit write:** `bodyMass`, `bodyMassIndex`, `bodyFatPercentage`, `leanBodyMass`  
**HealthKit read:** those plus fitness digest types for monitoring / Coach context  

Muscle, bone, water %, visceral index, raw ohms: **in-app only**.

### Legal disclaimer

Shown **once** in onboarding and again under **Settings → Legal** only. Never in Coach chat, Progress roast, or notification copy.

---

## Protocol (scale)

Mi Scale 2 **broadcasts**; no pairing required for a live reading.

| Bytes (`0x181B` service data) | Meaning |
|-------------------------------|---------|
| 0 | Unit (`bit0` lbs; else kg) |
| 1 | Flags: impedance / stabilized / weight removed |
| 2-8 | Timestamp |
| 9-10 | Impedance ohms (LE uint16) |
| 11-12 | Weight raw (LE uint16): ÷200 → kg |

Composition numbers are reverse-engineered estimates, not clinical lab values. Not medical advice.

**Quirks:** name usually `MIBFS`; ignore unstabilized / weight-removed frames; impedance `0` or `≥ 3000` invalid; socks / wet feet → weight-only.

Sources: ESPHome `xiaomi_miscale`, Theengs XMTZC05HM, openScale / MIBCS reverse-engineering.

---

## Project layout

```
TheScale/
  TheScale.xcodeproj/
  Config/                 # TheScale.xcconfig, Secrets.example.xcconfig
  TheScale/               # SwiftUI app (BLE, HealthKit, Coach, FM, UI)
  TheScaleTests/
workers/grok-proxy/       # Cloudflare Worker (XAI_API_KEY secret)
scripts/validate_decode.py
docs/                     # Architecture, Coach/AI, Health/notifications
```

## Docs

| Doc | Contents |
|-----|----------|
| [docs/architecture.md](docs/architecture.md) | Planes, data flow, layout |
| [docs/coach-and-ai.md](docs/coach-and-ai.md) | Grok Worker, streaming, FM hybrid, memory |
| [docs/health-and-notifications.md](docs/health-and-notifications.md) | HealthKit, Progress, alerts, FM polish |

## Version

Bump **MARKETING_VERSION** and **CURRENT_PROJECT_VERSION** together in the Xcode target when shipping code. Docs-only commits may leave the number unchanged.
