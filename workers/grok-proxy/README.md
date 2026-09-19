# The Scale Grok proxy

Cloudflare Worker that holds the shared xAI API key. Every The Scale install calls this HTTPS endpoint; the key never lives in Settings or (when using this path) in the IPA.

## One-time setup on Alex’s Mac

```bash
cd workers/grok-proxy
npx wrangler secret put XAI_API_KEY
# paste the key at the prompt (never into chat / git)
npx wrangler deploy
```

Copy the printed `*.workers.dev` URL into:

`TheScale/Config/Secrets.xcconfig`

```
GROK_PROXY_URL = https://the-scale-grok.YOUR_SUBDOMAIN.workers.dev
GROK_API_KEY =
```

Rebuild / reinstall the app so Info.plist picks up the URL. Users never paste a key.
