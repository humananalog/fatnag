# Health and notifications

## HealthKit

| Direction | Types |
|-----------|--------|
| **Write** | `bodyMass`, `bodyMassIndex`, `bodyFatPercentage`, `leanBodyMass` |
| **Read** (only what Coach / charts / algorithms use) | Weight + fat % for charts; `heartRate`, `restingHeartRate`, `heartRateVariabilitySDNN`, `respiratoryRate`, `appleSleepingWristTemperature`, `oxygenSaturation`, `vo2Max`, `stepCount`, `activeEnergyBurned`, `appleExerciseTime`, `sleepAnalysis` (stages when Watch writes them), `distanceWalkingRunning`, workouts |

Writes happen only on **Confirm to Health** or **Manual → Save**. Manual entries set `HKMetadataKeyWasUserEntered`.

**Monday morning card (2.8.0+ / 2.50.4):** after a successful write, if local time is Monday 04:00-12:00, the app presents the weekly instructor card (progress + Sunday target + meals + Grok diagnostic). Cached per ISO week. Progress week-start kg = last Monday Health body mass (prefer morning 04:00–12:00; else any Monday sample; else last weigh before Tuesday); anchor date is always local Monday 00:00. Weekly % / Sunday target pace from that Monday kg. Preview anytime: Settings → Legal → **Dev** (ephemeral — does not reset live weekly progress).

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

**Important:** FATNAG reads **HealthKit only**. Apps like AllTrails or Strava appear only after they write workouts/distance into Apple Health.

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
- **WEEK START** reads `session.weeklyGoalSurface.weekStartKg`, built by `WeeklyGoalSurfaceEngine` from persisted `weeklyGoal` after `ensureWeeklyGoalBaseline()` → `MondayCardEngine.reconcileWeekStart` (Health/history last-Monday rule above).
- Offline roast or live Grok orchestrator when consented + configured.

## Notification surfaces

All local (`UNUserNotificationCenter`). Toggles live in Settings. **2.9.0+** ships iOS 27-era chrome:

| Surface | Title / subtitle / body | Category actions | Thread | Interruption |
|---------|-------------------------|------------------|--------|--------------|
| Coach wake | Name + wake · clock/before · Coach line | Open Coach, Snooze 10 min | `thescale.coach` | **Time Sensitive** |
| Coach reminder | Name + reminder · fire time · Coach line | Open Coach, Snooze | `thescale.coach` | Active |
| Morning weigh drill | Keel · 💩 drill · **06:30** local fallback (or ASAP after Health wake); window closes **08:00**; skips if already weighed today | Open Coach / Weigh | `thescale.coach` | **Time Sensitive** |
| Bad trend | Name + scale check · kg · reason | Open History, Progress, Snooze | `thescale.trend` | Active |
| Monday mini-goal | Name + weekly · goal title · nudge | Open Progress, Coach | `thescale.trend` | Passive |
| Weigh miss ladder | Soft evening / day 2–3 | Open Weigh, Snooze | `thescale.trend` | Active |
| Monday skip | Mon noon if still empty | Open Progress | `thescale.trend` | Passive |
| Sunday wrap | Soft week wrap (≥1 weigh) | Open Progress | `thescale.trend` | Passive |
| Fitness interval | Name + check · interval · open hint | Open Coach | `thescale.fitness` | Passive |
| Watch / pre-sleep HR | Name + signal · kind · message | Open Coach, Snooze | `thescale.fitness` | Active |
| Dev sample | Name + sample · kg · QA line | Open Coach, Progress | `thescale.sample` | Active |

Also: Communication-style Coach avatar when appropriate (`INSendMessageIntent` / `UNNotificationAttributedMessageContext`), PNG attachment visuals, `relevanceScore`, `targetContentIdentifier`, App Intents (`OpenCoachIntent`, `OpenProgressIntent`, `OpenHistoryIntent`). Foreground: wake gets banner+sound+list+badge; interval/weekly stay quieter (banner+list).

| Trigger | Gate | Copy |
|---------|------|------|
| Bad trend (above ideal + rising, or sharp weekly gain) | Algorithmic + ≥3 distinct weigh days/7d + ≥3d between fires + daily budget | FM polish after schedule (optional suppress) |
| Monday mini-goal | Pref + Mon weigh still missing before noon (one-shot 08:15, not repeating) | Schedule first, FM polish optional |
| Morning weigh drill (2.50.0+) | Pref on + auth; **before 08:00 local**; skip if already weighed today; **idempotent** fallback (no re-add spam) | Default **06:30** local (migrates legacy 07:30); sleep-wake ASAP when Health has wake; max once/day; vulgar 💩 Keel copy |
| Weigh miss ladder (1.0.45+) | Pref morning drill; evening same-day after 08:00 empty; day 2–3 soft drift; ≤1/day ≤3/week; daily budget | Gentle, never Time Sensitive |
| Monday skip (1.0.45+) | Pref weekly; Mon ≥12:00 still empty; once/ISO week | Soft Progress |
| Sunday wrap (1.0.45+) | Pref weekly; Sun ≥18:00; ≥1 weigh this week; once/ISO week | Soft Progress |
| Global daily budget (1.0.45+) | ≤2 non-morning banners/day (morning / Coach wake / spike exempt) | — |
| Coach-scheduled wake / reminder | Coach parse → **schedule first** | FM polish optional (never blocks) |
| Fitness (Watch wear / pre-sleep HR) | Algorithm + cooldown + daily budget | FM judgment + polish |
| Fitness interval nudge | Monitor interval | FM polish |

**Rule:** algorithms decide *whether work exists* and schedule local notifications; Foundation Models may refine wording afterward and may drop weak *trend/fitness* pings. Coach wake/timed reminders and morning weigh always schedule with algorithmic copy first. If Apple Intelligence is off or ineligible, algorithmic strings still fire (no silent drop regression).

### Morning weigh drill (2.50.0+)

- Default fallback clock **06:30** local (replaces legacy **07:30** when still on that default).
- Morning window closes at **08:00** local — no same-day fire at/after 8.
- Skip if any body-mass / weigh-in already logged for the **local calendar day** (before 8am gate aligns with that day).
- Copy: title `Keel · 💩 drill`, body `Go drop a 💩 and use FATNAG after!` (Keel/sergeant, Time Sensitive unchanged).
- Settings **Send test drill** uses the same 💩 copy; docs note ~06:30 / before 8:00.
- Loss delta surfaces a clear **minus** (`-650g`) + "You're a winner" on post-weigh hero, home, Progress, and History.

### Morning weigh drill (2.36.0+)

Fallback schedule is **idempotent**: if a pending `thescale.morning-weigh-fallback` already targets the same local fire instant (±60s), consider() does not remove/re-add (stops DEBUG log spam on every digest/observer wake).

`Date` debug prints show **UTC** (`+0000`). For Asia/Hong_Kong, **06:30 local next morning** appears as **22:30 UTC** the prior calendar day. Triggers use `Calendar.current` date components + `timeZone`.

### Morning weigh drill (2.35.0+)

Rules:

1. Max **once per local day**.
2. Never schedule or deliver at or after **08:00** local (was 09:00 before 2.50).
3. If HealthKit bodyMass (or in-app save) already logged today → cancel wake + fallback for today; arm tomorrow only.
4. Calendar fallback default **06:30** (clamped before 08:00).

**Already weighed detection:** any `bodyMass` sample dated today in `recentHealthWeights` (HealthKit refresh), `historyWeights`, or `historyTrendWindowWeights`.

### Morning weigh drill (2.34.0 notes)

Root cause of "no pings all day": sleep-wake path required a live HealthKit wake inside a 3 min-2.5 h window and BG wakes skipped when only morning coaching was on. No calendar fallback existed.

Fix:

1. Auth requests include **Time Sensitive**.
2. BG `runBackgroundHealthWake` runs when **morning weigh** is on (fetches sleep digest).
3. Calendar fallback `thescale.morning-weigh-fallback` always pending when the toggle is on (next eligible local morning clock).
4. Settings: denied status surfaced, fallback clock picker, **Send test drill now**.
5. Home bell sheet lists pending with next fire times + the same test button.

**Verify:**

1. Settings → Notifications: status **allowed** (or tap Allow / System if denied).
2. Morning weigh drill ON. Fallback clock e.g. 06:30.
3. Home bell → Pending should list `morning fallback` with tomorrow/today fire time.
4. Tap **Send test drill now** (Settings or Alerts sheet). Expect 💩 Keel banner ~2s later (Time Sensitive).
5. Coach still: `remind me in 2 minutes` for timed reminder path.

### Coach reminders (2.7.2+)

- Parse → auth → **algorithmic `UNUserNotificationCenter.add` first** → optional FM polish of pending content.
- Past fire dates are bumped (near-term +65s, calendar +1 day) so iOS can deliver.
- Near-term asks use interval triggers; Settings lists pending Coach reminders with cancel.
- Focus/DND can still silence banners even when auth is allowed.

**Coach reminder verify (quick):**

1. Settings → Notifications: status should show **allowed** plus banner/sound/badge/time-sensitive lines (or tap Request permission / System Settings).
2. Coach: `remind me in 2 minutes`.
3. Expect an in-chat confirm with the **exact local fire time**, and Settings → Coach reminders lists the pending row.
4. Lock phone or leave app; banner should land ~2 minutes later (Focus/DND can silence it). Long-press for Open Coach / Snooze.
5. For morning: `remind me at 8am` (or `remind me tomorrow morning at 8am`). Confirm the locked local time in chat + Settings pending list.

**Dev sample SOTA ping:** Settings → Legal → **Dev** → **Fire sample SOTA notification**. Expect ~1.5s later: titled sample with subtitle kg, visual, Coach chrome, actions.

### Fitness monitoring + HealthKit background (2.9.0+)

- Settings: enable, interval (manual / 6h / 12h / daily / morning+evening), pre-sleep HR window + bpm threshold.
- Elevated or missing HR ~30 min before sleep (HRV-aware when present); sparse HR despite movement/distance → Watch-not-worn nudge.
- Automated Grok checks send one orchestrator answer with digest + memory + persona when interval is due.
- **Background wiring (real, not open-app-only):**
  1. `UIBackgroundModes`: `healthkit`, `fetch`, `processing`.
  2. Entitlement: `com.apple.developer.healthkit.background-delivery`.
  3. `HealthKitBackgroundDelivery` calls `enableBackgroundDelivery` + `HKObserverQuery` for workouts (immediate), sleep (immediate), body mass (immediate), steps/energy/HR/HRV/RHR (hourly — Apple’s floor for steps).
  4. Observer wake → `runBackgroundHealthWake`: refresh digest, evaluate Watch-wear / pre-sleep triggers, schedule local notifications (cooldowns apply), refresh bad-trend when weight samples change. Full Grok/FM coach reply only when forced or interval-due.
  5. Backups: `BGAppRefreshTask` (`app.thescale.ios.fitness-check`) + `BGProcessingTask` (`app.thescale.ios.fitness-processing`).
- **Honesty:** iOS coalesces and throttles HealthKit background delivery and BG tasks. Not guaranteed realtime. Observers still fire without the UI being open; Focus/DND can silence banners.
- If Grok is offline, FM can summarize a private digest for the in-app path.

**Verify background Health wake:**

1. Pull `main` **2.9.0**, Clean Build, Run on iPhone 15.
2. Settings → Allow Health access; enable **Health ↔ Grok monitoring** + notify on triggers.
3. Confirm Settings shows **Health background: N observers** (not “not armed”).
4. Start a workout on Apple Watch (or log one that writes to Health), then **lock the phone** and leave FATNAG in background / killed.
5. When Health syncs the workout (or sleep / steps burst), expect FATNAG to wake briefly and, if algorithms fire, a local notification (Watch-wear / interval / etc.) **without opening the app**.
6. Optional Xcode: Debug → Simulate Background Fetch; or console filter `HealthKitBackground`.

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
4. Delivered notification: uses name, Coach voice, no em dashes, no AI markers. Long-press shows actions; wake may show as Communication-style Coach.

Parent overview: [README](../README.md). AI routing: [coach-and-ai.md](coach-and-ai.md).
