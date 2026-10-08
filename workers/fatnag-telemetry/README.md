# fatnag-telemetry

Anonymous product usage aggregates for FATNAG + password-gated admin dashboard.

## Setup

```bash
cd workers/fatnag-telemetry
npx wrangler kv namespace create EVENTS
# paste id into wrangler.toml

npx wrangler secret put APP_SHARED_SECRET   # same as the-scale-grok
npx wrangler secret put ADMIN_PASSWORD

npx wrangler deploy
```

Dashboard: `https://fatnag-telemetry.<account>.workers.dev/admin`

## Privacy

- No chat text, no Health samples, no IDFA
- Stable anonymous device UUID only
- Soft opt-out in Settings (`ScaleTelemetry.isEnabled`)
