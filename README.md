# The Scale

Privacy-first iOS app for Alex’s **Xiaomi Mi Body Composition Scale 2** (model **XMTZC05HM** / label variant **XMTZCOSHM** → treat as XMTZC05HM). Replaces Zapp Lite for weighing: BLE on-device only, results into **Apple Health**.

**Version:** 1.7.0  
**Target device:** iPhone 15 (iOS 17+)  
**Deployment target:** iOS 17.0 (iPhone only)  
**Signing team (Mac Mini):** Human Analog Limited `XHVW66YM39`  
**Bundle id:** `app.thescale.ios`

## What it does

1. Scans for the scale’s BLE advertisements (`MIBFS` / service data `0x181B`)
2. Opens a **full-screen live weigh-in sheet** as soon as a scale is selected; one viewport (no ScrollView); content-first layout (atmosphere is background only so decorative washes cannot widen the sheet); system safe-area + 24pt horizontal inset; weight dominant with body fat % / lean %, trend, edit/confirm on one screen
3. Keeps **body fat %** and **lean %** visible during the live session and in edit-before-save (impedance stays internal for BIA)
4. Reads recent **Apple Health** body-mass history (on-device) and colors the sheet by trend vs last weight: **green** loss, **yellow** stable (±0.2 kg), **red** gain
5. Estimates body composition on-device (fat %, water %, muscle, bone, BMI, visceral index)
6. Lets you **edit** weight / fat % / lean % **before** confirm
7. **Home** is sparse: brand, **Find Scale**, **History**, **Manual**, optional **Weigh in**. Profile, ideal weight, calibration, and Health permissions copy live under the gear (**Settings**)
8. **Calibration uses the same live sheet** (from Settings): enter reference mass, open live sheet, weigh that mass, store offset/factor on-device
9. On confirm, writes **weight, BMI, body fat %, lean body mass** to HealthKit
10. After a successful Health save (and anytime via home **History**), opens charts for weight kg + body fat % from HealthKit (default **Last 2 weeks**). Ideal line from Settings; domain includes all Health samples. Optional **Trend** projects weight to ideal from the last 2 weeks (OLS). Tap a point for its value. **Manual** logs mass-only while travelling.

No accounts, no backend, no analytics, no third-party cloud.

## Privacy model

| Data | Where it goes |
|------|----------------|
| Weight / impedance from the scale | Parsed in memory on the iPhone |
| Height / age / sex / ideal weight / ideal fat % | `UserDefaults` on device only |
| Weight calibration (factor / offset) | `UserDefaults` on device only |
| Health **read** | Recent `bodyMass` for trend; `bodyMass` + `bodyFatPercentage` for history charts |
| Health **writes** | Apple Health (HealthKit) on device, after **Confirm to Health** or **Manual → Save** |
| Network | None by design |

HealthKit types:

- Read: `bodyMass`, `bodyFatPercentage`
- Write: `bodyMass`, `bodyMassIndex`, `bodyFatPercentage`, `leanBodyMass`

Muscle mass, bone mass, water %, visceral fat, and raw ohms are **shown in-app only**. HealthKit has no first-class quantities for those.

**Trend threshold (live sheet):** ±0.2 kg vs the most recent Health weight counts as stable.

### History charts

- Series are **Apple Health** `bodyMass` / `bodyFatPercentage` for the selected range (never a local-only fake series).
- Ideal weight draws as a dotted Ideal line; Y domain includes every Health sample (no clipping below ideal).
- **Trend** toggle: OLS linear regression on the last **14 days** of Health weights; projects forward until the line crosses ideal; labels the crossing date + kg. Fat chart stays Health-only (no projection).
- Tap a sample for a selection callout.
- **Manual** (home or History): mass/kg only, optional when (default now), writes weight + BMI with `HKMetadataKeyWasUserEntered`, then opens History.

### Weight chart Y-axis (ideal)

Ideal weight from Settings is a dotted **Ideal** reference line. The plot domain is `min(dataMin, ideal)…max(dataMax, ideal, projection) + padding` so real Health points are never clipped. Body fat chart: when ideal body fat % is set, same Ideal line pattern; otherwise auto-scale with labeled highest / lowest.

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
xcodebuild build -scheme TheScale -sdk iphoneos -configuration Debug -destination 'generic/platform=iOS'
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
2. When you tap **Confirm to Health**, allow write access for weight / BMI / body fat / lean body mass, and read for weight + body fat history charts.
3. If denied earlier: Settings → The Scale → enable Bluetooth; Settings → Health → Data Access → The Scale.

### First weigh-in

1. Gear → **Settings**: height, age, sex, **ideal weight** (floors the history weight chart), optional ideal body fat %.
2. Optional calibration (Settings only): set reference mass (default **5 kg** or Alex’s **7.926 kg**), tap **Weigh reference on live sheet**. Place that mass, wait for raw kg, tap **Store calibration**. Same live sheet as a normal weigh-in; does not write to Health.
3. Home → **Find Scale**; select `MIBFS` / Mi Scale → live weigh-in opens.
4. Stand **barefoot** until fat % / lean % appear. Allow Health read when prompted for trend colors.
5. **Edit** if needed; only **Confirm to Health** writes.
6. After save, **History** opens (also reachable anytime from home **History**). Ranges: 1W, 2W (default), 1M, 3M, 1Y.
7. Health app → Browse → Body Measurements to verify.

### Unit tests (Mac)

```bash
cd TheScale
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -scheme TheScale -destination 'platform=iOS Simulator,name=iPhone 17'
```

Decoder / composition / chart math are unit-tested; they do **not** replace on-device BLE + HealthKit verification.

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
  TheScaleTests/      # Decoder + composition + chart unit tests
scripts/
  validate_decode.py  # Cross-check frame decode without Xcode
```

## Version

Marketing version **1.6.0** / build **14**. Bump both in the Xcode target when shipping changes.
