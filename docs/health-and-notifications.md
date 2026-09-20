# Health and notifications

## HealthKit

| Direction | Types |
|-----------|--------|
| **Write** | `bodyMass`, `bodyMassIndex`, `bodyFatPercentage`, `leanBodyMass` |
| **Read** | Weight + fat % for charts/trend; plus `heartRate`, `restingHeartRate`, `stepCount`, `activeEnergyBurned`, `sleepAnalysis`, `distanceWalkingRunning`, workouts for fitness digest |

Writes happen only on **Confirm to Health** or **Manual → Save**. Manual entries set `HKMetadataKeyWasUserEntered`.

In-app only (no HealthKit quantity): muscle mass, bone mass, water %, visceral index, raw ohms.

### Coach live path (2.7.1+)

Every Coach chat turn calls `refreshFitnessDigestForCoach()` before Grok sees the brief. That is separate from background fitness-monitor jobs.

Digest includes:

- Steps, active energy, resting/latest HR, sleep, workouts in last 24h
- **Recent workouts** (up to 5; type, end time, duration, **distance km**, kcal, source) over a 90-day lookback, all activity types (Hiking, Walking, Running, Other, third-party)
- **Walking/running distance** totals (24h + 7d). If Workouts are empty but 24h distance ≥ ~3 km, Coach is told Health shows a distance spike without a Workout sample
- Access / honesty lines so Coach says "allow Health / enable third-party Health sync" instead of inventing activity

**Important:** The Scale reads **HealthKit only**. Apps like AllTrails or Strava appear only after they write workouts/distance into Apple Health. An AllTrails hike that never synced to Health will correctly look empty to Coach.

Settings → **Health ↔ Grok monitoring** shows **Health status**, **Allow Health access**, and **Open Health**. Ask Coach: `what was my last workout?` or `insights from my hike`.

### Coach distance / third-party (2.7.3+)

1. Allow Health access (Workouts + Walking/Running Distance).
2. If you track in AllTrails (or similar), enable **write to Apple Health** in that app.
3. Confirm the workout (or distance) appears in the Apple Health app.
4. Ask Coach about the hike/workout. Expect distance km + source when Health has samples; expect an honest "not in Health / check app sync" when it does not.

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
| Coach-scheduled wake / reminder | Coach parse → **schedule first** | FM polish optional (never blocks) |
| Fitness (Watch wear / pre-sleep HR) | Algorithm + cooldown | FM judgment + polish |
| Fitness interval nudge | Monitor interval | FM polish |

**Rule:** algorithms decide *whether work exists* and schedule local notifications; Foundation Models may refine wording afterward and may drop weak *trend/fitness* pings. Coach wake/timed reminders always schedule with algorithmic copy first. If Apple Intelligence is off or ineligible, algorithmic strings still fire (no silent drop regression).

### Coach reminders (2.7.2+)

- Parse → auth → **algorithmic `UNUserNotificationCenter.add` first** → optional FM polish of pending content.
- Past fire dates are bumped (near-term +65s, calendar +1 day) so iOS can deliver.
- Near-term asks use interval triggers; Settings lists pending Coach reminders with cancel.
- Focus/DND can still silence banners even when auth is allowed.

**Coach reminder verify (quick):**

1. Settings → Notifications: status should be **allowed** (or tap Request permission / System Settings).
2. Coach: `remind me in 2 minutes`.
3. Expect an in-chat confirm with the **exact local fire time**, and Settings → Coach reminders lists the pending row.
4. Lock phone or leave app; banner should land ~2 minutes later (Focus/DND can silence it).
5. For morning: `remind me at 8am` (or `remind me tomorrow morning at 8am`). Confirm the locked local time in chat + Settings pending list.

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
