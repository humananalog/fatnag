# App Store Connect — iPhone 6.5" screenshots

Upload to **App Store → iOS App → 6.5" Display**.

**Required size:** `1284 × 2778` (portrait). Also accepted: `1242 × 2688`.

## Files (gallery order)

| # | File | Surface |
|---|------|---------|
| 1 | `01-home.png` | Weekly goal / day gauges |
| 2 | `02-weigh.png` | Live weigh-in settled |
| 3 | `03-progress.png` | Progress tab |
| 4 | `04-charts.png` | Weight history / charts |
| 5 | `05-coach.png` | Keel Coach |
| 6 | `06-paywall.png` | Unlock Coach (Annual) |
| 7 | `07-meals.png` | Meals |

Raw simulator masters (pre-resize) live in `raw/`.

## Regenerate

```bash
./TheScale/scripts/capture-asc-iphone-65-screenshots.sh
```

Do **not** upload DEBUG menus, plan overrides, or sample-notification buttons.

Captures always use `-promoShot=` so **notification + HealthKit permission sheets never appear**. UI uses the demo persona’s in-memory Health digest (no share-sheet during screenshot runs).
