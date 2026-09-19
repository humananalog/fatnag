# The Scale Grok proxy

Cloudflare Worker that holds the shared xAI API key. Every The Scale install calls this HTTPS endpoint; the key never lives in Settings or (when using this path) in the IPA.

## One-time setup on Alex’s Mac

```bash
cd workers/grok-proxy
npx wrangler secret put XAI_API_KEY
# paste the key at the prompt (never into chat / git)
npx wrangler deploy
```

Canonical Xcode include: `TheScale/Config/TheScale.xcconfig` (Debug + Release `baseConfigurationReference`).
That file already sets the shared proxy URL (non-secret). Optional gitignored override: `Secrets.xcconfig`.

```
GROK_PROXY_URL = https://the-scale-grok.the-scale-grok.workers.dev
GROK_API_KEY =
```

Rebuild / reinstall the app so Info.plist picks up the URL. Users never paste a key. Never put `XAI_API_KEY` in an xcconfig that is tracked.
