# StoreKit + Human Analog (FATNAG)

Wire the real paywall against **Human Analog Limited** (team `XHVW66YM39`, bundle `app.thescale.ios`). Do not rely on the DEBUG plan override when validating purchases.

## Product IDs (must match code + ASC)

| Plan | Product ID | Price (marketing) | Credits / week |
|------|------------|-------------------|----------------|
| Plus | `app.thescale.ios.plus.monthly` | $2 / month | 28 |
| Pro  | `app.thescale.ios.pro.monthly`  | $8 / month | 120 |

Subscription group name: **Coach** (see `Config/Products.storekit`).

Code: `ScalePlan.storeProductID`, `ScaleStorefront`, `ScaleSubscriptionStore`.

## Lane 1: Local StoreKit config (default Debug)

Use this on Simulator / Mac Mini Debug builds. No App Store Connect sandbox account required.

1. Open `TheScale.xcodeproj`.
2. Scheme **TheScale** → Edit Scheme → Run → Options.
3. **StoreKit Configuration** = `Config/Products.storekit` (already set in the shared scheme).
4. Settings → Coach plan → **Use StoreKit** (clears any DEBUG override).
5. Open the paywall → Buy Plus / Pro. System sheet should show local prices.
6. Settings commerce line should read **Local StoreKit (Human Analog config)** and list loaded products.

Reset local purchases: Xcode → Debug → StoreKit → Manage Transactions → Delete, or erase the Simulator.

## Lane 2: Human Analog App Store Connect sandbox (device)

Use this before TestFlight / App Review.

### One-time ASC setup (Human Analog)

1. Sign in to [App Store Connect](https://appstoreconnect.apple.com) as Human Analog (`XHVW66YM39`).
2. Apps → **FATNAG** (bundle `app.thescale.ios`). Create the app record if missing.
3. Monetization → Subscriptions → create group **Coach** if needed.
4. Add auto-renewable subscriptions:
   - Reference: Plus Monthly → Product ID `app.thescale.ios.plus.monthly` → 1 month → $2.00 (or local equivalent).
   - Reference: Pro Monthly → Product ID `app.thescale.ios.pro.monthly` → 1 month → $8.00.
5. Localization + review screenshot / notes as ASC requires.
6. Privacy Policy URL: `https://humananalog.github.io/the-scale/privacy` (`ScaleLegal.privacyPolicyURL`).
7. Agreements, Tax, and Banking must be Active for the Human Analog legal entity or products stay empty.

### Sandbox Apple ID

1. ASC → Users and Access → Sandbox → Testers → create a Sandbox Apple ID.
2. On device: Settings → Developer → Sandbox Apple Account (or App Store sign-out, then buy once and sign in when prompted).
3. Build Debug or TestFlight to a physical iPhone signed with team `XHVW66YM39`.
4. **Clear DEBUG plan override** (Settings → Use StoreKit).
5. For device builds that should hit ASC sandbox instead of the local file: Edit Scheme → Run → Options → StoreKit Configuration → **None**, then run on device.
6. Paywall → purchase. Receipts come from Apple sandbox under Human Analog.

## Lane 3: DEBUG override (quota only)

Settings → **DEBUG plan override** forces Free / Plus / Pro without StoreKit. Useful for quota UX only.

- Purchases fail while override is on (intentional).
- Tap **Use StoreKit** before any real paywall test.

## Verify

```bash
# Unit tests (product IDs + plans)
xcodebuild -scheme TheScale -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TheScaleTests/CoachQuotaTests \
  -only-testing:TheScaleTests/ScaleStorefrontTests \
  test
```

In app:

1. Settings commerce line shows loaded product IDs + prices.
2. Paywall buttons show StoreKit `displayPrice`, not only hard-coded marketing copy.
3. Buy → plan badge updates → weekly Keel credits match Plus (28) or Pro (120).
4. Restore purchases returns the same entitlement (paywall shows “Restored Plus/Pro” or “No active…found”).
5. Empty catalog: with StoreKit config detached and ASC products missing, paywall shows **Subscriptions unavailable** + Retry (Release), not a silent dead Buy button.

## Common failures

| Symptom | Fix |
|---------|-----|
| 0 products loaded | Scheme missing `Products.storekit`, or ASC products not Ready to Submit / agreements inactive |
| Purchase says DEBUG override | Settings → Use StoreKit |
| Sandbox buy fails on device with config file still attached | Set StoreKit Configuration to None for that run |
| Wrong team | Signing team must be `XHVW66YM39` (Human Analog) |

## Related

- Agent Store handoff: `docs/feedback-rating-sandbox-handoff.md` (exact Alex checklist)
- `Config/Products.storekit` - local catalog
- `TheScale.xcodeproj/xcshareddata/xcschemes/TheScale.xcscheme` - attaches the config on Run
- `ScaleSubscriptionStore` / `PaywallView` / Settings Coach plan card
