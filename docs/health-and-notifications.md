# Health and notifications

## HealthKit

| Direction | Types |
|-----------|--------|
| **Write** | `bodyMass`, `bodyMassIndex`, `bodyFatPercentage`, `leanBodyMass` |
| **Read** | Weight + fat % for charts/trend; plus `heartRate`, `restingHeartRate`, `stepCount`, `activeEnergyBurned`, `sleepAnalysis`, workouts for fitness digest |

Writes happen only on **Confirm to Health** or **Manual → Save**. Manual entries set `HKMetadataKeyWasUserEntered`.

In-app only (no HealthKit quantity): muscle mass, bone mass, water %, visceral index, raw ohms.

### History charts

- Series always from Apple Health for the selected range (not a local fake series).
- Ideal weight / ideal fat % as dotted Ideal lines; domain includes all samples.
- **Trend** toggle: OLS on last **14 days** of weights; tempered projection (safe kg/wk caps + fitness modulators) until ideal; fat chart has no projection.
- Live weigh-in trend color vs last Health weight: ±0.2 kg = stable (yellow).

## Progress

- Weekly mini-goal (editable Δ kg), progress bar.
- Offline roast or live Grok orchestrator when consented + configured.

## Notification surfaces

All local (`UNUserNotificationCenter`). Toggles live in Settings.

| Trigger | Gate | Copy |
|---------|------|------|
| Bad trend (above ideal + rising, or sharp weekly gain) | Algorithmic | FM polish + optional suppress |
| Monday mini-goal | Pref | FM polish |
| Coach-scheduled wake / reminder | Coach parse → schedule | FM polish |
| Fitness (Watch wear / pre-sleep HR) | Algorithm + cooldown | FM judgment + polish |
| Fitness interval nudge | Monitor interval | FM polish |

**Rule:** algorithms decide *whether work exists*; Foundation Models decide *wording* and may drop weak pings. If Apple Intelligence is off or ineligible, algorithmic strings still fire (no silent drop regression).

### Fitness monitoring

- Settings: enable, interval (manual / 6h / 12h / daily / morning+evening), pre-sleep HR window + bpm threshold.
- Elevated or missing HR ~30 min before sleep; sparse HR despite movement → Watch-not-worn nudge.
- Automated Grok checks send one orchestrator answer with digest + memory + persona.
- `BGAppRefresh` is best-effort; repeating local nudges ask you to open the app. Foreground resume runs due checks.
- If Grok is offline, FM can summarize a private digest for the in-app path.

## Legal

Medical disclaimer: onboarding + Settings → Legal only. Notification and Coach copy must not recite it.

## Verify smarter notifications

1. Enable Apple Intelligence; wait for model.
2. App Settings → Apple Intelligence: on-device ready.
3. Bad-trend weigh-in **or** Coach: `ping me tomorrow morning before 7:30 to wake up`.
4. Delivered notification: uses name, Coach voice, no em dashes, no AI markers.

Parent overview: [README](../README.md). AI routing: [coach-and-ai.md](coach-and-ai.md).
