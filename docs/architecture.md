# Architecture

FATNAG is a native iOS app. BLE and HealthKit stay on-device. Optional coaching leaves the device only through an operator-managed Cloudflare Worker. On-device Apple Intelligence handles private notification polish and light assist when available.

## Planes

| Plane | Responsibility |
|-------|----------------|
| **App (iPhone)** | BLE decode, BIA estimates, SwiftUI UI, calibration, charts, Progress, local notifications |
| **HealthKit** | Persist weight / BMI / fat % / lean mass; supply history + fitness digest |
| **UserDefaults** | Profile, persona, calibration, Coach memory, notification prefs |
| **Foundation Models** | On-device `SystemLanguageModel` / `LanguageModelSession` (Apple Intelligence) |
| **ScaleOnDevicePolish** | Metal 0.5B sidecar for non-AI iPhones (`Packages/ScaleOnDevicePolish`) |
| **Grok proxy Worker** | Holds `XAI_API_KEY`; requires `APP_SHARED_SECRET`; rate limits + weekly KV caps; streams or returns Grok completions |
| **xAI Grok** | Full Coach chat + specialist consults behind one user-facing voice |

```
Mi Scale 2 ──BLE ads──► FATNAG ──write/read──► Apple Health
                           │
                           ├── UserDefaults (local state)
                           ├── Foundation Models (on-device, AI phones)
                           ├── ScaleOnDevicePolish (0.5B Metal, other iPhones)
                           └── HTTPS (consent) -> Worker -> Grok
```

## App modules (Swift)

| Area | Role |
|------|------|
| `BLE/` | Scan + parse `MIBFS` / `0x181B` frames |
| `BodyComposition/` | On-device estimates from weight + impedance + profile |
| `Health/` | HealthKit authorize, read, write |
| `Models/` | Session VM, measurement, calibration |
| `Coaching/` | Grok client, shared config, memory, fitness monitor, FM helpers, targets |
| `OnDevicePolish/` | Host bridge for `ScaleOnDevicePolish` install gate |
| `Notifications/` | Bad-trend + Coach wake schedulers |
| `Views/` | Home, live weigh-in, History, Manual, Coach, Progress, Monday card, Settings, 3-step onboarding, soft App Review sheet |
| `Config/` | `TheScale.xcconfig` → Info.plist `GrokProxyURL` / `GrokAPIKey` / `GrokAppSecret` (secret via gitignored `Secrets.xcconfig`) |

## Onboarding (2.11.0+)

Three steps for adoption: **You** (name + freeform) → **Body** (height/age/sex/ideal) → **Confirm** (on-device FM / heuristics inferred persona + legal + soft notification opt-in). Permissions last. **2.11.1:** Foundation Models only for pre-fill (no Grok). DEBUG: home **DEBUG** capsule.

## App Review

After **6+** confirmed Health weigh-in saves, a soft star sheet may appear when home is idle. 4–5 stars → StoreKit `requestReview()` **once per install**; ≤3 → quiet opt-out. Soft dismiss / cooldown still apply if the user skips. Settings **Send feedback** posts to Supabase Edge Function `submit-feedback` (table `app_feedback` + Resend).

## Network rules

- Default: **no network**.
- Network only when Coach (or enabled fitness monitoring) runs with shared config **and** user consent.
- Broken / truncated proxy URLs must fail loudly (see xcconfig `https:/$()/` escape in [README](../README.md) and [coach-and-ai.md](coach-and-ai.md)).

## What never leaves the phone

Weigh-in frames, impedance, calibration math, and Health samples stay local unless the user opts into a Coach/fitness request. Even then, payloads are short digests plus relevant memory facts, not raw Health dumps or API keys.

See also: [coach-and-ai.md](coach-and-ai.md), [health-and-notifications.md](health-and-notifications.md).
