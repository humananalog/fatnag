# The Scale

Privacy-first iOS app for Alex’s **Xiaomi Mi Body Composition Scale 2** (model **XMTZC05HM** / label variant **XMTZCOSHM** → treat as XMTZC05HM). Replaces Zapp Lite for weighing: BLE on-device only, results into **Apple Health**.

**Version:** 1.3.0  
**Target device:** iPhone 15 (iOS 17+)  
**Deployment target:** iOS 17.0 (iPhone only)  
**Signing team (Mac Mini):** Human Analog Limited `XHVW66YM39`  
**Bundle id:** `app.thescale.ios`

## What it does

1. Scans for the scale’s BLE advertisements (`MIBFS` / service data `0x181B`)
2. Opens a **full-screen live weigh-in sheet** as soon as a scale is selected; one viewport (no ScrollView); system safe-area + 20pt horizontal inset (glass panels never edge-flush); weight dominant with resistance, trend, edit/confirm on one screen
3. Keeps **resistance (Ω)** visible during the live session and in edit-before-save; BIA is not hidden while weight streams
4. Reads recent **Apple Health** body-mass history (on-device) and colors the sheet by trend vs last weight: **green** loss, **yellow** stable (±0.2 kg), **red** gain
5. Estimates body composition on-device (fat %, water %, muscle, bone, BMI, visceral index)
6. Lets you **edit** weight / resistance / composition **before** confirm
7. **Calibration uses the same live sheet**: enter reference mass (default example **5 kg**), open live sheet, weigh that mass, store offset/factor on-device. Settings holds reference mass + reset; not a separate capture-only flow
8. On confirm, writes **weight, BMI, body fat %, lean body mass** to HealthKit

No accounts, no backend, no analytics, no third-party cloud.

## Privacy model

| Data | Where it goes |
|------|----------------|
| Weight / impedance from the scale | Parsed in memory on the iPhone |
| Height / age / sex profile | `UserDefaults` on device only |
| Weight calibration (factor / offset) | `UserDefaults` on device only |
| Health **read** | Recent `bodyMass` samples for on-device trend only |
| Health **writes** | Apple Health (HealthKit) on device, only after **Confirm to Health** |
| Network | None by design |

HealthKit types:

- Read: `bodyMass`
- Write: `bodyMass`, `bodyMassIndex`, `bodyFatPercentage`, `leanBodyMass`

Muscle mass, bone mass, water %, visceral fat, and raw ohms are **shown in-app only**. HealthKit has no first-class quantities for those.

**Trend threshold:** ±0.2 kg vs the most recent Health weight counts as stable.

## Protocol (honest notes)

The Mi Body Composition Scale 2 **broadcasts** measurements; it does not need pairing for a live reading.

**13-byte service data (`0x181B`) layout** (ESPHome / Theengs / openScale / ble-scale-sync):

| Bytes | Meaning |
|-------|---------|
| 0 | Unit control (`bit0` = lbs; else kg; catty via byte1 `bit6`) |
| 1 | Flags: `bit1` impedance present, `bit5` stabilized, `bit7` weight removed |
| 2-8 | Timestamp |
| 9-10 | Impedance ohms (LE uint16), when present |
| 11-12 | Weight raw (LE uint16): ÷200 → kg, ÷100 → lbs/catty |

Sources adapted:

- [ESPHome `xiaomi_miscale`](https://esphome.io/components/sensor/xiaomi_miscale/)
- [Theengs Decoder XMTZC05HM](https://decoder.theengs.io/devices/XMTZC05HM.html)
- [lolouk44/xiaomi_mi_scale body metrics](https://github.com/lolouk44/xiaomi_mi_scale)
- openScale / prototux MIBCS reverse-engineering (via ble-scale-sync `MiScaleCalc`)

**Limitations**

- The hardware sends **weight + impedance only**. Fat/muscle/water/bone are **estimates** from reverse-engineered Xiaomi formulas; they can differ from Zapp/Zepp by a few points.
- Not medical advice; BIA foot-to-foot scales are approximate.
- Simulator cannot verify real BLE or HealthKit end-to-end. Confirm on the iPhone 15.

## Mac Mini local checkout

Path that should already exist (no re-clone needed if present):

```bash
cd /Users/alexclaw/Projects/project-zero
git checkout main
git pull origin main
open TheScale/TheScale.xcodeproj
```

If CLI tools still point at Command Line Tools instead of Xcode.app:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# or one-shot:
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

If Xcode says **“iOS 26.5 is not installed”** for device/simulator destinations:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -downloadPlatform iOS
# or: Xcode → Settings → Platforms / Components → download iOS 26.5
```

Smoke-build without a phone attached:

```bash
cd /Users/alexclaw/Projects/project-zero/TheScale
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -scheme TheScale -sdk iphoneos -configuration Debug
```

## Run on iPhone 15 (required)

BLE advertisements and HealthKit need a **physical iPhone**. The Simulator will not exercise the real scale path.

### Prerequisites

- Mac Mini with **Xcode** (this machine has Xcode 26.6 / iOS 26.5 SDK)
- Team **Human Analog Limited** (`XHVW66YM39`) already wired in the project
- iPhone 15 on **iOS 17 or later**, unlocked, Developer Mode on if prompted
- USB-C cable (or wireless debugging after first pair)
- Mi Body Composition Scale 2 with working batteries

### Xcode setup

1. Open `TheScale/TheScale.xcodeproj` in Xcode.
2. Select the **TheScale** target → **Signing & Capabilities**:
   - Team: **Human Analog Limited** (`XHVW66YM39`)
   - Bundle id: `app.thescale.ios`
   - HealthKit capability already present via `TheScale/Resources/TheScale.entitlements`
3. Plug in the **iPhone 15**, unlock it, tap **Trust** if asked.
4. Destination: select your **iPhone 15** (not a simulator).
5. Product → **Run** (⌘R).
6. First launch on device: Settings → General → VPN & Device Management → trust the **Human Analog Limited** / Apple Development certificate if iOS blocks the app.

### Permissions on the phone

1. When The Scale asks for **Bluetooth**: Allow.
2. When you tap **Save to Apple Health**, allow write access for weight / BMI / body fat / lean body mass.
3. If denied earlier: Settings → The Scale → enable Bluetooth; Settings → Health → Data Access → The Scale.

### First weigh-in

1. Open **Settings** (gear): set height, age, and sex (local composition math only).
2. Optional calibration: set reference mass (default **5 kg** or Alex’s **7.926 kg**), tap **Weigh reference on live sheet** (or home **Calibrate with live sheet**). Place that mass on the scale, wait for raw kg, tap **Store calibration**. Same live sheet as a normal weigh-in; does not write to Health.
3. Tap **Find Scale**; look for `MIBFS` / Mi Scale.
4. Select the scale: the **live weigh-in sheet** opens immediately and streams weight. The **Resistance** panel stays visible (shows `- Ω` until BIA arrives). Text must have left/right padding (not flush to the bezel).
5. Stand **barefoot** until ohms appear in the Resistance panel. Allow Health read access when prompted so the sheet can color by trend.
6. Tap **Edit** if any field needs correction (weight and resistance are both editable). Only **Confirm to Health** writes.
7. With impedance, Health gets weight + BMI + body fat % + lean mass. Weight-only saves weight + BMI only (confirm prompt).
8. Open the Health app → Browse → Body Measurements and confirm values appeared.

### Unit tests (Mac)

```bash
cd TheScale
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -scheme TheScale -destination 'platform=iOS Simulator,name=iPhone 17'
```

Decoder / composition math are unit-tested; they do **not** replace on-device BLE + HealthKit verification.

Optional Linux/Mac reference check of the same frame math:

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

Marketing version **1.3.0** / build **9**. Bump both in the Xcode target when shipping changes.
