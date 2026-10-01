# Pricing and weekly Grok quota

Industry-standard tier names: **Free**, **Plus**, **Pro**.

| Plan | Price | Weekly live Grok credits | Intent |
|------|-------|--------------------------|--------|
| Free | $0 | 5 | Full scale / Health / charts / on-device Coach; Grok teaser |
| Plus | $1.99 / month · $19.99 / year | 28 (~4 / day) | Active daily Coach without burning margin |
| Pro | $7.99 / month · $79.99 / year | 120 (~17 / day) | Power users / heavy chat + fitness digest days |

## Product rules

- Every tier keeps the **full app experience** (weigh-in, Health sync, charts, Monday card UI, notifications, Foundation Models polish when eligible).
- Phones **without** Apple Intelligence (iPhone XR / iOS 18, etc.) may use a **light Grok polish** for home advice / banner rewrite when Metal sidecar is not ready. Caps: Free **1**/week, Plus **4**, Pro **10**, and always leave chat credits reserved (Free 2 / Plus 4 / Pro 8). At most **one** light network polish per local day.
- Only **live Grok** network calls consume credits (chat turn, Monday card rewrite, fitness Grok check, meal plan, light assist). Each counts as **1** credit; specialist consults behind a chat turn do not add extra burns (`X-Scale-Credit: 0` on the Worker).
- Credits reset each **ISO week** (Monday). Exhausted Free → unlock Plus; exhausted Plus → unlock Pro; Pro waits for Monday.
- Model: `grok-4.20-non-reasoning` (Human Analog console). Avoid reasoning SKUs for COGS.

## Server-side enforcement (Worker)

Client `CoachWeeklyQuota` (UserDefaults) is UX only. The Cloudflare Worker (`the-scale-grok`) enforces the same Free **5** / Plus **28** / Pro **120** caps in KV, keyed by anonymous device id + UTC ISO week. See [workers/grok-proxy/README.md](../workers/grok-proxy/README.md).

| Divergence | Detail |
|------------|--------|
| Week boundary | iOS uses the device calendar; Worker uses **UTC** ISO week. Near Monday UTC midnight, counts can disagree briefly. Server wins for spend. |
| Plan claim | Worker trusts `X-Scale-Plan` from the app until App Store receipt verification lands. Shared secret + rate limits raise the abuse bar. |

## StoreKit

- Plus monthly: `app.thescale.ios.plus.monthly` ($1.99)
- Plus annual: `app.thescale.ios.plus.annual` ($19.99 — ~2 months free vs monthly)
- Pro monthly: `app.thescale.ios.pro.monthly` ($7.99)
- Pro annual: `app.thescale.ios.pro.annual` ($79.99 — ~2 months free vs monthly)
- USD uses App Store **X.99** price points (not whole dollars).
- Paywall defaults to **Annual**; Monthly is a top selector.
- Local DEBUG: scheme uses `TheScale/Config/Products.storekit`
- App Store Connect: create all four product IDs in one subscription group before shipping.

## Margin note

At ~$1.25–$2.50 / 1M tokens for 4.20 NR, Plus’s 28 short turns/week stay near a ~$0.50 COGS target after Apple’s cut when prompts stay compact. Measure real token usage before raising Free or shipping annual SKUs.
