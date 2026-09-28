# fatnag.com domain setup (GoDaddy → Cloudflare → Vercel)

## What’s already done

| Layer | Status |
|-------|--------|
| **Vercel project** `fatnag-com` (team Human Analog) | Created. Domains `www.fatnag.com` + `fatnag.com` → 308 to www. Preview: `https://fatnag-com.vercel.app` |
| **Cloudflare Pages** `fatnag-com` | Live mirror at `https://fatnag-com.pages.dev` (full Support / Privacy / Terms) |
| **Site source** | `sites/fatnag-com/` in the fatnag repo |
| **Cloudflare zone `fatnag.com`** | **Not created yet** — Wrangler OAuth lacks `zone.create`. Add the site once in the dashboard (below). |

Architecture (same pattern as `orio.bike` / `humananalog.ai`):

1. **GoDaddy** = registrar only (nameservers → Cloudflare)
2. **Cloudflare** = DNS (+ optional orange-cloud proxy later)
3. **Vercel** = origin for `www.fatnag.com`

---

## A. Cloudflare — add the zone (one-time, ~2 minutes)

1. Sign in: https://dash.cloudflare.com/login (account for `alexhuther@proton.me` / Human Analog).
2. **Add a domain** → enter `fatnag.com` → continue.
3. Plan: **Free** is enough.
4. Cloudflare shows two nameservers, e.g. `xxxx.ns.cloudflare.com` and `yyyy.ns.cloudflare.com`. **Copy both.**
5. Skip or finish the DNS import wizard (we will set records next).

### DNS records in Cloudflare (DNS only / grey cloud)

After the zone exists, create:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| **CNAME** | `www` | `cname.vercel-dns.com` | DNS only (grey) |
| **A** | `@` | `76.76.21.21` | DNS only (grey) |

Optional apex alias: Vercel already redirects `fatnag.com` → `www.fatnag.com` (308) once the A record resolves.

> Prefer Cloudflare Pages instead of Vercel for this static site? CNAME `www` → `fatnag-com.pages.dev` and remove the Vercel project domains first (only one host should own the hostname).

---

## B. GoDaddy — point nameservers at Cloudflare

Do this **after** Cloudflare shows the assigned nameservers.

1. GoDaddy → **My Products** → **Domains** → **fatnag.com** → **DNS** / **Nameservers**.
2. Choose **Change nameservers** → **I’ll use my own nameservers** (or “Custom”).
3. Replace GoDaddy defaults (`ns51.domaincontrol.com` / `ns52.domaincontrol.com`) with the **two Cloudflare nameservers** from step A.
4. Save. Propagation: usually 15 minutes–few hours (can be up to 48h).

Do **not** keep Domain Control nameservers if you want Cloudflare DNS. While GoDaddy still owns DNS you can temporarily add the same A/CNAME records under GoDaddy DNS instead of switching NS — then later move NS to Cloudflare.

### Temporary GoDaddy-only DNS (skip Cloudflare zone for now)

If you want `www` live before adding the Cloudflare zone:

| Type | Name | Value |
|------|------|--------|
| CNAME | `www` | `cname.vercel-dns.com` |
| A | `@` | `76.76.21.21` |
| Forwarding (optional) | `fatnag.com` | https://www.fatnag.com |

---

## C. Verify

```bash
dig NS fatnag.com +short          # should show Cloudflare NS after switch
dig www.fatnag.com +short        # should show Vercel / CF answers
curl -sI https://www.fatnag.com/support/ | head
curl -sI https://fatnag.com/support/ | head   # expect 308 → www
```

App Store / in-app URLs can then move from `humananalog.github.io/fatnag/...` to:

- https://www.fatnag.com/support
- https://www.fatnag.com/privacy
- https://www.fatnag.com/terms

---

## D. After Cloudflare zone exists — tell the agent

Reply with the two Cloudflare nameservers (or “zone added”). We can then:

1. Confirm DNS records via API
2. Flip `ScaleLegal` URLs to `www.fatnag.com`
3. Commit / bump / push
