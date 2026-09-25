# Apple Watch & Live Activities (ship gate)

## Shipped for 1.0 (iPhone)

| Surface | Status |
|---------|--------|
| Weigh-in **Live Activity** + Dynamic Island | Shippable. `WeighInLiveActivityController` + `TheScaleWidgets` Live Activity target. Starts/updates/ends with live weigh-in; gracefully no-ops if Live Activities disabled. |
| Local notifications mirrored to Watch | Shippable via iOS “Mirror iPhone Alerts” (system). No native watchOS app required. |

## Post-1.0 (do not block submit)

| Surface | Status |
|---------|--------|
| Native **watchOS** app / complications | Not started. No Watch target in the project. |
| Watch-only Sunday kg glance | Not started. |
| Home Screen / Lock Screen **widgets** (non–Live Activity) | Not shipped. Widget extension currently contains **Live Activity only**. |

## Rule

Do **not** advertise a Watch app or home-screen widgets in App Store screenshots/copy until those targets exist. Live Activities during weigh-in are fine to show.

## Next Watch slice (when scheduled)

1. Add `TheScale Watch App` target (SwiftUI) with Sunday kg from App Group / HealthKit.
2. Complication: circular Sunday target kg.
3. Optional Watch Connectivity to mirror live weigh-in state.

Keep HealthKit reads on Watch thin; prefer App Group snapshot written by iPhone after weigh-in.
