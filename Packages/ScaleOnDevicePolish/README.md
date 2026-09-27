# ScaleOnDevicePolish

Consumer on-device polish sidecar for FATNAG.

## Why

Apple Intelligence / Foundation Models need A17 Pro+ (iPhone 15 Pro) or A18+ (iPhone 16).
Base iPhone 15 and older eligible phones do not get that model. This package installs a
**Qwen2.5 0.5B Instruct (Q4_K_M)** GGUF and runs short polish / classify jobs on **Metal**
via llama.cpp.

## Device policy (no clutter)

| Device | Sidecar |
|--------|---------|
| Apple Intelligence capable (15 Pro / 16+) | **Never installed** (use Foundation Models) |
| Not AI-eligible, iPhone with Metal + enough RAM | **Auto-install** after onboarding (Wi-Fi preferred) |
| Simulator / low memory | Install skipped; algorithmic fallback |

The host app passes `appleIntelligenceDeviceCapable` from `SystemLanguageModel` availability
(`deviceNotEligible` → sidecar; any other AI state → no sidecar).

## Jobs

Mirrors Foundation Models polish surfaces:

- Notification title/body rewrite
- Weak-ping judgment
- Short private digest summary
- Light memory fact extract
- Onboarding profile JSON assist

Full Coach chat stays on the Keel / Grok Worker path.

## Install size

~470 MB GGUF downloaded into Application Support (not bundled in the IPA).
Engine: llama.cpp XCFramework (~binaryTarget `b5046`).

## Host integration

```swift
import ScaleOnDevicePolish

OnDevicePolishBootstrap.shared.configure(
  appleIntelligenceDeviceCapable: !isDeviceNotEligibleForAppleIntelligence
)
await OnDevicePolishBootstrap.shared.ensureInstalledIfEligible()
```

Then call `OnDevicePolishService.shared.refineNotificationCopy(...)` when Foundation Models
are unavailable and `OnDevicePolishService.shared.isReady`.
