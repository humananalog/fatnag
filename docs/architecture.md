# Architecture

The Scale is a native iOS app. BLE and HealthKit stay on-device. Optional coaching leaves the device only through an operator-managed Cloudflare Worker. On-device Apple Intelligence handles private notification polish and light assist when available.

## Planes

| Plane | Responsibility |
|-------|----------------|
| **App (iPhone)** | BLE decode, BIA estimates, SwiftUI UI, calibration, charts, Progress, local notifications |
| **HealthKit** | Persist weight / BMI / fat % / lean mass; supply history + fitness digest |
| **UserDefaults** | Profile, persona, calibration, Coach memory, notification prefs |
| **Foundation Models** | On-device `SystemLanguageModel` / `LanguageModelSession` (Apple Intelligence) |
| **Grok proxy Worker** | Holds `XAI_API_KEY`; streams or returns Grok completions |
| **xAI Grok** | Full Coach chat + specialist consults behind one user-facing voice |

```
Mi Scale 2 ──BLE ads──► The Scale ──write/read──► Apple Health
                           │
                           ├── UserDefaults (local state)
                           ├── Foundation Models (on-device)
                           └── HTTPS (consent) ──► Worker ──► Grok
```

## App modules (Swift)

| Area | Role |
|------|------|
| `BLE/` | Scan + parse `MIBFS` / `0x181B` frames |
| `BodyComposition/` | On-device estimates from weight + impedance + profile |
| `Health/` | HealthKit authorize, read, write |
| `Models/` | Session VM, measurement, calibration |
| `Coaching/` | Grok client, shared config, memory, fitness monitor, FM helpers, targets |
| `Notifications/` | Bad-trend + Coach wake schedulers |
| `Views/` | Home, live weigh-in, History, Manual, Coach, Progress, Settings, onboarding |
| `Config/` | `TheScale.xcconfig` → Info.plist `GrokProxyURL` / `GrokAPIKey` |

## Network rules

- Default: **no network**.
- Network only when Coach (or enabled fitness monitoring) runs with shared config **and** user consent.
- Broken / truncated proxy URLs must fail loudly (see xcconfig `https:/$()/` escape in [README](../README.md) and [coach-and-ai.md](coach-and-ai.md)).

## What never leaves the phone

Weigh-in frames, impedance, calibration math, and Health samples stay local unless the user opts into a Coach/fitness request. Even then, payloads are short digests plus relevant memory facts, not raw Health dumps or API keys.

See also: [coach-and-ai.md](coach-and-ai.md), [health-and-notifications.md](health-and-notifications.md).
