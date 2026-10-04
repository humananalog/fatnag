# App Store Connect — iPhone 6.5" simulator captures (legacy)

These are device-chrome simulator stills, **not** the marketing mocks used for store upload.

**Upload the promo set instead:** [`../README.md`](../README.md) (`iphone-6.5/` at 1284×2778).

## Files (old gallery)

| # | File | Surface |
|---|------|---------|
| 1 | `01-home.png` | Weekly goal / day gauges |
| 2 | `02-weigh.png` | Live weigh-in settled |
| 3 | `03-progress.png` | Progress tab |
| 4 | `04-charts.png` | Weight history / charts |
| 5 | `05-coach.png` | Keel Coach |
| 6 | `06-paywall.png` | Unlock Coach (Annual) |
| 7 | `07-meals.png` | Meals |

Regenerate simulator stills:

```bash
./TheScale/scripts/capture-asc-iphone-65-screenshots.sh
```

Do **not** upload DEBUG menus, plan overrides, or sample-notification buttons.
Captures always use `-promoShot=` so permission sheets never appear.
