# Apple Watch (this pass)

## Shipped

- **iPhone morning weigh drill** mirrors to paired Apple Watch when Watch mirrors iPhone alerts (system default).
- Copy and coalesce live on iPhone; Watch shows the same local notification when Mirror iPhone Alerts is on.

## Not in this pass

- No native watchOS target / complications yet.
- No Watch-only Sunday kg glance UI.

## Next slice (when scheduled)

1. Add `TheScale Watch App` target (SwiftUI) with:
   - Sunday kg from shared App Group / HealthKit on Watch
   - One CTA: open companion / log weigh reminder
2. Complication: circular Sunday target kg
3. Optional Watch Connectivity to mirror live weigh-in state

Keep HealthKit reads on Watch thin; prefer App Group snapshot written by iPhone after weigh-in.
