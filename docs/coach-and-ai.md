# Coach and AI

Hybrid routing: **Grok Worker** for full Coach chat; **Foundation Models** (Apple Intelligence) or the **0.5B Metal polish sidecar** for private on-device polish and light assist.

## Grok Coach

- One user-facing voice (orchestrator). Medical / fitness / anatomy specialists consult behind the scenes when needed.
- Tone: badass, dark humour, sometimes vulgar. No em dashes. No "as an AI" tells.
- **Streaming:** app sends `stream: true`; Worker pipes xAI SSE into the chat UI.
- **Consent:** Settings → **Allow Grok coach requests**. No per-user key paste.
- **Persona + memory:** inject into prompts from on-device stores.
- **Targets:** Coach-stated goals update profile after `TargetFeasibility` gates.
- **Time-aware:** local clock in context; evening/night bans gym-lift next-actions.
- **HealthKit on every turn (2.7.1+ / science 2.7.4+):** Coach refreshes a dated Fitness digest (sleep stages, HRV, RHR, load/steps, workouts + distance, recovery band, optional SpO2/VO2/respiratory/wrist temp) before each ask. Missing metrics stay missing; Coach must not invent them or claim AllTrails access.
- **Monday weekly card (2.8.0+ / 2.50.4):** after a Monday-morning Confirm-to-Health (or Manual), Grok streams a one-screen instructor card (progress, Sunday kg goal paced to target weight + optional goal date, meals, energy-balance diagnostic). Cached for the ISO week. Progress week-start = last Monday Health weight (Monday morning preferred). No medical disclaimer on the card. Dev: Settings → Legal → **Dev** → Preview / Regenerate (**ephemeral**; does not rewrite live week-start / progress %).
- **SOTA notifications + HealthKit background (2.9.0+):** local banners use title/subtitle/body, categories/actions, threads, optional Communication Coach chrome + PNG visuals. `HKObserverQuery` + `enableBackgroundDelivery` (and BG refresh/processing backups) refresh digests and fire Watch-wear / pre-sleep / trend pings without opening the app. iOS still throttles.
- **Plans + weekly Grok quota (2.10.0+):** Free / Plus ($2/mo) / Pro ($8/mo). Full weigh-in, Health, charts, and on-device Coach on every plan. Live Grok (chat, Monday card, fitness check) burns ISO-week credits: Free 5, Plus 28 (~4/day active), Pro 120. Exhausted → paywall unlocks the next tier; Monday card / fitness fall back to on-device copy. StoreKit products `app.thescale.ios.plus.monthly` / `app.thescale.ios.pro.monthly`. Local testing: `Config/Products.storekit`. Live model: `grok-4.20-non-reasoning`.
- **3-step onboarding + soft stars (2.11.0+):** identity freeform → body basics → confirm inferred persona/diet/language. **2.11.1:** pre-fill uses **on-device Foundation Models** (Apple Intelligence) with heuristic fallback; no Grok network call. DEBUG builds show a home **DEBUG** button to reset onboarding / review prompts. After 3 confirmed weigh-ins, a soft star sheet can open StoreKit review for 4-5 stars only.

### Shared proxy setup

```bash
cd workers/grok-proxy
npx wrangler secret put XAI_API_KEY
npx wrangler deploy
```

Tracked non-secret URL in `TheScale/Config/TheScale.xcconfig`:

```
GROK_PROXY_URL = https:/$()/the-scale-grok.the-scale-grok.workers.dev
GROK_API_KEY =
```

Xcode `.xcconfig` treats `//` as a comment. A literal `https://…` silently becomes `https:` and breaks with `NSURLErrorDomain -1000`. Always use `https:/$()/host`.

Optional gitignored `Secrets.xcconfig` can override URL or bake a key (IPA-extractable; prefer Worker). Intentionally empty config → offline mock replies. Revoke for a user by turning off consent.

Worker notes: [workers/grok-proxy/README.md](../workers/grok-proxy/README.md).

## Foundation Models (Apple Intelligence)

Requires eligible device + Apple Intelligence enabled + model ready.

| Job | FM | Grok |
|-----|----|------|
| Notification title/body polish | Prefer | No |
| Ping noise filter (`shouldSendPing`) | Prefer (allow if FM off) | No |
| Coach wake reminder copy | Prefer polish **after** schedule | Timing stays local notifications; polish never blocks |
| Private fitness digest summary when Grok offline | Prefer | - |
| Memory fact extraction | Optional `@Generable` pass | Heuristic + Grok context when consented |
| Full multi-agent Coach chat | No | Prefer when consent + live config |

Code: `FoundationModelAvailability`, `FoundationModelCoach` (`LanguageModelSession`). Settings status + Coach `FM ready` / `FM off` badge.

## On-device polish sidecar (2.51.0)

For iPhones that are **not** Apple Intelligence capable (including base iPhone 15). AI-capable phones never download it.

| Piece | Detail |
|-------|--------|
| Package | `Packages/ScaleOnDevicePolish` (consumer SPM + llama.cpp Metal XCFramework b5046) |
| Model | Qwen2.5 0.5B Instruct Q4_K_M (~470 MB), downloaded to Application Support (Wi-Fi preferred) |
| Gate | `SystemLanguageModel` `deviceNotEligible` → install; eligible hardware → skip |
| Jobs | Same polish surfaces as FM via `FoundationModelCoach` fallback |
| UX | Settings status, download progress, retry; Coach badge `Polish ready` |

Host bridge: `OnDevicePolishBootstrap`. Auto-install after onboarding.

## Legal disclaimer

Exact copy lives in `CoachCopySanitize.medicalDisclaimer`. Shown **only**:

1. Onboarding (once)
2. Settings → Legal

Never appended to chat, Progress roast, or notifications. Client sanitizer strips model-injected disclaimer / AI-tell boilerplate.

## Verify (device)

1. Pull `main`, Clean Build, Run on iPhone 15.
2. Coach: consent, short ask → bubble streams (not one blob).
3. `curl -s https://the-scale-grok.the-scale-grok.workers.dev` → ok + `stream: true`.
4. FM (15 Pro / 16+): enable Apple Intelligence → Settings status ready → trigger alert / wake reminder.
5. Sidecar (iPhone 15 / other non-AI): after onboarding on Wi-Fi, Settings shows download then Polish ready; trigger alert / wake reminder.
6. Coach reminders (2.7.2+): `remind me in 2 minutes` → exact local time in chat + Settings pending list → banner lands.

See [health-and-notifications.md](health-and-notifications.md) for alert surfaces.

## Female coach voice (2.52.0)

When profile sex is female, Keel uses a nurturing, praise-heavy, funny coach tone for Grok, Apple Intelligence, and the Metal polish sidecar. Daily energy and protein targets are phrased as visual plates (palm of protein, fist of carbs, handful of greens) instead of leading with bare calorie figures. Pace lines avoid jargon like ETA.
