# The Scale

Privacy-first iOS app for Alex’s **Xiaomi Mi Body Composition Scale 2** (model **XMTZC05HM** / label variant **XMTZCOSHM** → treat as XMTZC05HM). Replaces Zapp Lite for weighing: BLE on-device only, results into **Apple Health**.

**Version:** 1.0.0  
**Target device:** iPhone 15 (iOS 17+)  
**Deployment target:** iOS 17.0 (iPhone only)

## What it does

1. Scans for the scale’s BLE advertisements (`MIBFS` / service data `0x181B`)
2. Decodes stabilized weight + impedance from the public 13-byte Mi Scale 2 frame
3. Estimates body composition on-device (fat %, water %, muscle, bone, BMI, visceral index)
4. On confirm, writes **weight, BMI, body fat %, lean body mass** to HealthKit

No accounts, no backend, no analytics, no third-party cloud.

## Privacy model

| Data | Where it goes |
|------|----------------|
| Weight / impedance from the scale | Parsed in memory on the iPhone |
| Height / age / sex profile | `UserDefaults` on device only |
| Health writes | Apple Health (HealthKit) on device, only after you tap **Save to Apple Health** |
| Network | None by design |

HealthKit share types requested (write-only; no read types):

- `bodyMass`
- `bodyMassIndex`
- `bodyFatPercentage`
- `leanBodyMass`

Muscle mass, bone mass, water %, visceral fat, and raw ohms are **shown in-app only** — HealthKit has no first-class quantities for those.

## Protocol (honest notes)

The Mi Body Composition Scale 2 **broadcasts** measurements; it does not need pairing for a live reading.

**13-byte service data (`0x181B`) layout** (ESPHome / Theengs / openScale / ble-scale-sync):

| Bytes | Meaning |
|-------|---------|
| 0 | Unit control (`bit0` = lbs; else kg; catty via byte1 `bit6`) |
| 1 | Flags: `bit1` impedance present, `bit5` stabilized, `bit7` weight removed |
| 2–8 | Timestamp |
| 9–10 | Impedance ohms (LE uint16), when present |
| 11–12 | Weight raw (LE uint16): ÷200 → kg, ÷100 → lbs/catty |

Sources adapted:

- [ESPHome `xiaomi_miscale`](https://esphome.io/components/sensor/xiaomi_miscale/)
- [Theengs Decoder XMTZC05HM](https://decoder.theengs.io/devices/XMTZC05HM.html)
- [lolouk44/xiaomi_mi_scale body metrics](https://github.com/lolouk44/xiaomi_mi_scale)
- openScale / prototux MIBCS reverse-engineering (via ble-scale-sync `MiScaleCalc`)

**Limitations**

- The hardware sends **weight + impedance only**. Fat/muscle/water/bone are **estimates** from reverse-engineered Xiaomi formulas; they can differ from Zapp/Zepp by a few points.
- Not medical advice; BIA foot-to-foot scales are approximate.
- Cloud VM / Simulator cannot verify real BLE or HealthKit end-to-end — Alex must confirm on the iPhone 15.

## Run on iPhone 15 (required)

BLE advertisements and HealthKit need a **physical iPhone**. The Simulator will not exercise the real scale path.

### Prerequisites

- Mac with **Xcode 15+** (iOS 17 SDK)
- Apple ID (free team is enough for personal device install)
- iPhone 15 on **iOS 17 or later**
- USB-C cable (or wireless debugging after first pair)
- Mi Body Composition Scale 2 with working batteries

### Xcode setup

1. Open `TheScale/TheScale.xcodeproj` in Xcode.
2. Select the **TheScale** target → **Signing & Capabilities**:
   - Choose your **Team**
   - Confirm bundle id `app.thescale.ios` (or change it if taken)
   - Confirm **HealthKit** capability (entitlements file is already wired)
3. Destination: select your **iPhone 15** (not a simulator).
4. On the phone: Settings → Privacy → allow **Bluetooth** and later **Health** prompts from The Scale.
5. Product → **Run** (⌘R).

### First weigh-in

1. Enter height, age, and sex in the app (used only for local composition math).
2. Tap **Find Scale** — look for `MIBFS` / Mi Scale.
3. Select the scale, then step on **barefoot** and stand still.
4. Wait until weight **and** impedance appear (impedance needs skin contact on the electrodes).
5. Tap **Save to Apple Health** and confirm the success state.
6. Open the Health app → Browse → Body Measurements to verify samples.

### Unit tests (Mac)

```bash
cd TheScale
xcodebuild test -scheme TheScale -destination 'platform=iOS Simulator,name=iPhone 15'
```

Decoder / composition math are unit-tested; they do **not** replace on-device BLE + HealthKit verification.

Optional Linux reference check of the same frame math:

```bash
python3 scripts/validate_decode.py
```

## Known scale quirks

- Advertise name is usually **`MIBFS`**. Model label may print `XMTZCOSHM`; treat as **XMTZC05HM**.
- Unstabilized / weight-removed frames are ignored on purpose.
- Impedance `0` or `≥ 3000` is treated as invalid (same as ESPHome).
- Socks, wet feet, or stepping off early → weight-only reading (no composition / no fat% Health write).
- Keep the iPhone near the scale; BLE ads are short-range.
- Body-composition estimates need a sane profile (height/age/sex). Wrong profile → wrong estimates, not wrong weight.

## Project layout

```
TheScale/
  TheScale.xcodeproj/
  TheScale/           # SwiftUI app (BLE, HealthKit, UI)
  TheScaleTests/      # Decoder + composition unit tests
scripts/
  validate_decode.py  # Cross-check frame decode without Xcode
```

## Version

Marketing version **1.0.0** / build **1**. Bump both in the Xcode target when shipping changes.
