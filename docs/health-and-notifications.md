# Health and notifications

## HealthKit

| Direction | Types |
|-----------|--------|
| **Write** | `bodyMass`, `bodyMassIndex`, `bodyFatPercentage`, `leanBodyMass` |
| **Read** (only what Coach / charts / algorithms use) | Weight + fat % for charts; `heartRate`, `restingHeartRate`, `heartRateVariabilitySDNN`, `respiratoryRate`, `appleSleepingWristTemperature`, `oxygenSaturation`, `vo2Max`, `stepCount`, `activeEnergyBurned`, `appleExerciseTime`, `sleepAnalysis` (stages when Watch writes them), `distanceWalkingRunning`, workouts |

Writes happen only on **Confirm to Health** or **Manual → Save**. Manual entries set `HKMetadataKeyWasUserEntered`.

**Monday morning card (2.8.0+):** after a successful write, if local time is Monday 04:00-12:00, the app presents the weekly instructor card (progress + Sunday target + meals + Grok diagnostic). Cached per ISO week. Preview anytime: Settings → Legal → **Dev**.

In-app only (no HealthKit quantity): muscle mass, bone mass, water %, visceral index, raw ohms.

Skipped vanity reads (no coaching decision): flights climbed, stand hours, basal energy, etc.

### Coach live path (2.7.1+ / science digest 2.7.4+)

Every Coach chat turn calls `refreshFitnessDigestForCoach()` before Grok sees the brief. That is separate from background fitness-monitor jobs.

Digest is a **dated snapshot** (`Generated at`) and includes:

- Steps, active energy, Apple Exercise Time, resting/latest HR, HR samples today
- **HRV SDNN** (recent + ~7d median when available)
- Respiratory rate, sleeping wrist temperature delta, SpO2, VO2 max (each marked missing when absent)
- **Sleep last night:** total asleep hours, onset/wake, Core/Deep/REM/Awake stages when Health has them, ~7d average, bedtime consistency (onset std-dev hours)
- Pre-sleep average HR in the configured window before onset
- Workouts in last 24h + **recent workouts** (up to 5 / 90d) with distance km + kcal + source
- Walking/running distance (24h + 7d); spike note when ≥ ~3 km without a Workout
- Transparent **recovery heuristic** band (green/yellow/red/unknown) with factor lines
- Access / honesty lines so Coach never invents missing metrics or AllTrails access

**Important:** The Scale reads **HealthKit only**. Apps like AllTrails or Strava appear only after they write workouts/distance into Apple Health.

Settings → **Health ↔ Grok monitoring** shows **Health status**, **Allow Health access**, and **Open Health**. After upgrading, tap Allow again so iOS can grant new read types (schema bump). Ask Coach about sleep / recovery / HRV / last workout.

### Algorithms (scientific notes)

Documented in code (`HealthScienceMath`, `TargetFeasibility`, `HealthChartMath`) and summarized here. Coaching heuristics only — not clinical diagnosis.

| Algorithm | Formula / rule | Rationale |
|-----------|----------------|-----------|
| **Safe weight loss/gain caps** | Loss ≈ 0.7% body weight/wk (midpoint of 0.5–1%), clamped 0.25–1.0 kg/wk; gain ≈ 0.5%/wk capped 0.5 kg/wk | Common ACSM / obesity-medicine sustainable-loss ballpark |
| **History projection** | OLS on adaptive Health weight window; temper slope to safe caps; soft slowdown if elevated RHR, short sleep, low HRV vs median, or red recovery band | Sparse weigh-ins → OLS; tempering avoids unsafe “crash” rays on charts |
| **Pre-sleep HR** | Flag if avg HR in N min before sleep onset ≥ RHR+Δ or ≥ absolute floor; borderline + depressed HRV vs 7d median also flags | Sleep-onset window + autonomic load; HRV relative check when present |
| **Watch-wear** | Movement (steps / workout / energy / walking-running km) with sparse HR samples → likely not worn | HR vs activity mismatch |
| **Recovery / load band** | Additive score from sleep duration, deep sleep, HRV vs median, RHR, recent workout load → green ≥70 / yellow 45–69 / red <45 / unknown if thin | Transparent coaching band; factors listed in digest |

### Coach distance / third-party (2.7.3+)

1. Allow Health access (Workouts + Walking/Running Distance + new science types).
2. If you track in AllTrails (or similar), enable **write to Apple Health** in that app.
3. Confirm the workout (or distance) appears in the Apple Health app.
4. Ask Coach about the hike/workout. Expect distance km + source when Health has samples; expect an honest "not in Health / check app sync" when it does not.

### History charts

- Series always from Apple Health for the selected range (not a local fake series).
- Ideal weight / ideal fat % as dotted Ideal lines; domain includes all samples.
- **Trend** toggle: OLS on recent weights; tempered projection (safe kg/wk caps + fitness modulators including HRV/recovery) until ideal; fat chart has no projection.
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
- Elevated or missing HR ~30 min before sleep (HRV-aware when present); sparse HR despite movement/distance → Watch-not-worn nudge.
- Automated Grok checks send one orchestrator answer with digest + memory + persona.
- `BGAppRefresh` is best-effort; repeating local nudges ask you to open the app. Foreground resume runs due checks.
- If Grok is offline, FM can summarize a private digest for the in-app path.

## Legal

Medical disclaimer: onboarding + Settings → Legal only. Notification and Coach copy must not recite it.

## Verify science digest (2.7.4)

1. Pull `main` 2.7.4, Clean Build, Run on iPhone.
2. Settings → **Allow Health access** (re-prompt for HRV / sleep / SpO2 / etc.).
3. Confirm sleep (and ideally HRV) appear in the Apple Health app from Apple Watch.
4. Coach: `how was my sleep?` / `how's my recovery?`
   - Expect dated digest facts (hours, stages if present, HRV, recovery band).
   - Missing metrics must say **missing**, never invented.

## Verify smarter notifications

1. Enable Apple Intelligence; wait for model.
2. App Settings → Apple Intelligence: on-device ready.
3. Bad-trend weigh-in **or** Coach: `ping me tomorrow morning before 7:30 to wake up`.
4. Delivered notification: uses name, Coach voice, no em dashes, no AI markers.

Parent overview: [README](../README.md). AI routing: [coach-and-ai.md](coach-and-ai.md).
