# The Scale

Privacy-first iOS app for the **Xiaomi Mi Body Composition Scale 2** (XMTZC05HM; label variant XMTZCOSHM treated the same). Replaces Zapp Lite: BLE weigh-ins on-device only, results into **Apple Health**, optional **Coach** via a shared Grok Worker, and on-device **Apple Intelligence** for notification polish.

| | |
|------|--|
| **Version** | 2.36.0 (build 71) |
| **Device** | iPhone 15 (physical; BLE + HealthKit) |
| **Xcode / SDK** | Xcode 27, iOS 27 SDK |
| **Deployment** | iOS 26.0, iPhone only |
| **Bundle id** | `app.thescale.ios` |
| **Team** | Human Analog Limited (`XHVW66YM39`) |

No accounts. No analytics. Weigh-ins never leave the phone except into Apple Health. Users never paste an API key.

### App Store release checklist (2.9.1+)
- Privacy Manifest `PrivacyInfo.xcprivacy` ships in the app bundle
- In-app + web Privacy Policy (`docs/privacy-policy.md` → host at `ScaleLegal.privacyPolicyURL`; set that URL in App Store Connect)
- `ITSAppUsesNonExemptEncryption = false` (HTTPS only)
- Dev tools menu is **DEBUG-only** (stripped from Release / App Store)
- Enable **Time Sensitive** + **Communication Notifications** on the App ID in Apple Developer before Archive (entitlements are already in the project)
- Leave `GROK_API_KEY` empty for store IPAs; Worker holds `XAI_API_KEY`
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
- **Home weekly-goal hero (2.12.2+):** one composition (no home cards) with % + track haze, energy-balance advice, Meals carousel (Grok, day-keyed cache), daily targets. Coach chat type bumped. Tap % for Progress.
- Weekly mini-goal (Δ kg), progress bar, offline or live Grok roast
- **Monday morning card (2.8.0+):** after Confirm-to-Health (or Manual) on Monday local morning (04:00-12:00), full-screen week plan: last-week Δ, Sunday kg target paced to ideal + optional goal date, meals, Grok diagnostic. Cached per ISO week; regenerates on a new Monday weigh-in. Dev preview: Settings → Legal → **Dev**
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

### Apple Intelligence

1. iPhone: **Settings → Apple Intelligence & Siri** → on; wait for model download
2. App **Settings → Apple Intelligence**: expect on-device model ready
3. Trigger a bad-trend alert or Coach wake reminder; copy should use your name and Coach voice

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
