# FATNAG Grok proxy

Cloudflare Worker (`the-scale-grok`) that holds the shared xAI API key. Every FATNAG install calls this HTTPS endpoint; the master key never lives in Settings or the IPA.

When the iOS app sets `"stream": true` in the JSON body, this Worker **pipes** xAI's SSE (`text/event-stream`) without buffering the full completion. Non-stream POSTs still return a single JSON body (specialist consults, Progress roast, meal plans).

## Hardening (auth · rate limits · weekly caps)

| Control | Mechanism |
|---------|-----------|
| Shared app secret | Secret `APP_SHARED_SECRET`; iOS sends `X-Scale-App-Secret`. Fail closed if unset on Worker or missing in Release builds. |
| Device id | Required `X-Scale-Device-Id` (anonymous UUID from `ScaleAnonymousIdentity`). |
| Plan | `X-Scale-Plan: free\|plus\|pro` (client-asserted until StoreKit receipt verify). |
| Credit burn | `X-Scale-Credit: 1` (default) burns one weekly credit; `0` for specialist consults (matches app: consults do not add extra burns). |
| Burst rate limit | Cloudflare `ratelimits` binding: **30/min per IP**, **20/min per device**. |
| Weekly caps | KV `LIMITS`: Free **5**, Plus **28**, Pro **120** per **UTC ISO week** (Monday). Same numbers as `ScalePlan.weeklyGrokCredits`. |
| App Attest | Header `X-Scale-Attest-Assertion` reserved. Full verify is a follow-up. Optional `ATTEST_REQUIRED=1` returns `501` until verify lands. |

`XAI_API_KEY` stays a Worker secret only. Never put it in xcconfig for App Store builds.

### Divergence notes

- **Client vs server week boundary:** iOS `CoachWeeklyQuota` uses the device calendar; the Worker uses **UTC ISO week**. Near Monday midnight UTC, counts can disagree by a few hours. Server is authoritative for spend.
- **Plan trust:** Plus/Pro limits honor the client `X-Scale-Plan` header. A modified IPA can claim `pro`. Mitigations: shared secret (raises bar), rate limits, upcoming App Attest + App Store Server API receipt checks.
- **Client UserDefaults ledger** still gates UX before the network call; the Worker ledger cannot be cleared by deleting the app’s preferences.

## One-time setup on Alex's Mac

```bash
cd workers/grok-proxy

# 1) xAI master key (existing)
npx wrangler secret put XAI_API_KEY

# 2) App ↔ Worker shared secret (generate a long random string; same value goes in Secrets.xcconfig)
#    e.g. openssl rand -hex 32
npx wrangler secret put APP_SHARED_SECRET

# 3) KV for weekly caps (skip if wrangler.toml already has your account's id)
#    npx wrangler kv namespace create the-scale-grok-limits
#    → paste id into wrangler.toml [[kv_namespaces]] id = "..."

npx wrangler deploy
```

Optional: `npx wrangler secret put ALLOWED_ORIGINS` (comma-separated). Not required for native iOS.

### iOS xcconfig

Canonical tracked file: `TheScale/Config/TheScale.xcconfig` (Debug + Release `baseConfigurationReference`).

**xcconfig note:** never write `https://` literally (the `//` starts a comment). Use:

```
GROK_PROXY_URL = https:/$()/the-scale-grok.alexhuther.workers.dev
GROK_API_KEY =
GROK_APP_SECRET =
```

Put the shared secret only in the **gitignored** override:

```bash
cp TheScale/Config/Secrets.example.xcconfig TheScale/Config/Secrets.xcconfig
# edit Secrets.xcconfig:
# GROK_APP_SECRET = <same value as APP_SHARED_SECRET>
```

- **Release:** empty/missing `GROK_APP_SECRET` → fail closed (offline Coach).
- **Debug:** same fail closed; use `Secrets.xcconfig` for local live Coach.
- Rebuild / reinstall so Info.plist picks up `GrokAppSecret`.
- Never put `XAI_API_KEY` in any xcconfig.

### Local Worker unit check

```bash
node workers/grok-proxy/test/limits.test.mjs
```

### Health check

```bash
curl -s https://the-scale-grok.alexhuther.workers.dev
# → ok, auth: shared_secret, weekly_limits, attest: stub
```

Unauthenticated POST must return **401**.

## App Attest follow-up (not in this slice)

1. Enable App Attest capability; generate key + attest at first launch; store key id in Keychain.
2. iOS: before each Coach POST, create assertion; send `X-Scale-Attest-Assertion` (+ key id header).
3. Worker: verify with Apple App Attest API / DCAppAttest; bind assertion to device id + request hash.
4. Flip `ATTEST_REQUIRED=1` only after verify is implemented (today that flag returns 501 on purpose).
