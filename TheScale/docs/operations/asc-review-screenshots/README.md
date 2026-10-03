# ASC subscription Review Information screenshots

Upload the **matching** PNG to each Coach SKU (Apple X.99 price points).

| ASC product | Price | Screenshot |
|-------------|-------|------------|
| Plus Annual `app.thescale.ios.plus.annual` | $19.99 / year | `review-plus-annual.png` |
| Plus Monthly `app.thescale.ios.plus.monthly` | $1.99 / month | `review-plus-monthly.png` |
| Pro Annual `app.thescale.ios.pro.annual` | $79.99 / year | `review-pro-annual.png` |
| Pro Monthly `app.thescale.ios.pro.monthly` | $7.99 / month | `review-pro-monthly.png` |

## Regenerate

```bash
./TheScale/scripts/capture-asc-subscription-review.sh
```

## ASC steps

1. App Store Connect → FATNAG → Monetization → Subscriptions → **Coach**
2. Open each subscription → **Review Information**
3. Screenshot → Choose File → matching PNG above
4. Review Notes → paste from ASC StoreKit setup canvas (§5b)
5. Set USA price to the X.99 tier in the table (not $2 / $20 / $8 / $80)
6. Save
