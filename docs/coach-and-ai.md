# Coach and AI

Hybrid routing: **Grok Worker** for full Coach chat; **Foundation Models** for private, on-device polish and light assist.

## Grok Coach

- One user-facing voice (orchestrator). Medical / fitness / anatomy specialists consult behind the scenes when needed.
- Tone: badass, dark humour, sometimes vulgar. No em dashes. No "as an AI" tells.
- **Streaming:** app sends `stream: true`; Worker pipes xAI SSE into the chat UI.
- **Consent:** Settings → **Allow Grok coach requests**. No per-user key paste.
- **Persona + memory:** inject into prompts from on-device stores.
- **Targets:** Coach-stated goals update profile after `TargetFeasibility` gates.
- **Time-aware:** local clock in context; evening/night bans gym-lift next-actions.
- **HealthKit on every turn (2.7.1+ / science 2.7.4+):** Coach refreshes a dated Fitness digest (sleep stages, HRV, RHR, load/steps, workouts + distance, recovery band, optional SpO2/VO2/respiratory/wrist temp) before each ask. Missing metrics stay missing; Coach must not invent them or claim AllTrails access.
- **Monday weekly card (2.8.0+):** after a Monday-morning Confirm-to-Health (or Manual), Grok streams a one-screen instructor card (progress, Sunday kg goal paced to target weight + optional goal date, meals, energy-balance diagnostic). Cached for the ISO week. No medical disclaimer on the card. Dev: Settings → Legal → **Dev** → Preview / Regenerate.

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

## Legal disclaimer

Exact copy lives in `CoachCopySanitize.medicalDisclaimer`. Shown **only**:

1. Onboarding (once)
2. Settings → Legal

Never appended to chat, Progress roast, or notifications. Client sanitizer strips model-injected disclaimer / AI-tell boilerplate.

## Verify (device)

1. Pull `main`, Clean Build, Run on iPhone 15.
2. Coach: consent, short ask → bubble streams (not one blob).
3. `curl -s https://the-scale-grok.the-scale-grok.workers.dev` → ok + `stream: true`.
4. FM: enable Apple Intelligence → Settings status ready → trigger alert / wake reminder.
5. Coach reminders (2.7.2+): `remind me in 2 minutes` → exact local time in chat + Settings pending list → banner lands.

See [health-and-notifications.md](health-and-notifications.md) for alert surfaces.
