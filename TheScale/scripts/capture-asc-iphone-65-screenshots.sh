#!/usr/bin/env bash
# Capture clean iPhone 6.5" ASC screenshots (1284×2778) — no Health / notification sheets.
#
# Always launches with -promoShot=… so PromoCaptureMode skips permission UIs.
# In-memory demo persona drives the UI (HealthKit share sheet never presented).
#
# Usage:
#   ./TheScale/scripts/capture-asc-iphone-65-screenshots.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="$ROOT/TheScale/docs/operations/asc-screenshots/iphone-6.5"
SCHEME="${SCHEME:-TheScale}"
PROJECT="$ROOT/TheScale/TheScale.xcodeproj"
BUNDLE_ID="${BUNDLE_ID:-app.thescale.ios}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17}"
DERIVED="${DERIVED:-$ROOT/TheScale/build/asc-shot-derived}"
SETTLE_SECONDS="${SETTLE_SECONDS:-4.2}"
ASC_W=1284
ASC_H=2778
if [[ -z "${DEMO_FLAG:-}" ]]; then
  DEMO_FLAG="-demoMale"
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: Xcode not found at $DEVELOPER_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR/raw"

dismiss_system_sheets() {
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Simulator" to activate
delay 0.25
tell application "System Events"
  if not (exists process "Simulator") then return
  tell process "Simulator"
    set frontmost to true
    -- Prefer Allow / Turn On All so Health stays granted; also clear Notif sheet.
    repeat with btnName in {"Turn On All", "Allow", "Share", "OK", "Done", "Don’t Allow", "Don't Allow"}
      try
        click button (btnName as text) of window 1
        delay 0.2
      end try
      try
        click button (btnName as text) of sheet 1 of window 1
        delay 0.2
      end try
    end repeat
  end tell
end tell
APPLESCRIPT
}

echo "==> Booting simulator: $DEVICE_NAME"
xcrun simctl boot "$DEVICE_NAME" 2>/dev/null || true
if [[ -d "$DEVELOPER_DIR/Applications/Simulator.app" ]]; then
  open -a "$DEVELOPER_DIR/Applications/Simulator.app" >/dev/null 2>&1 || true
fi
sleep 1

UDID="$(
  xcrun simctl list devices booted -j | DEVICE_NAME="$DEVICE_NAME" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
want = os.environ["DEVICE_NAME"]
fallback = None
for _runtime, devs in d.get("devices", {}).items():
    for x in devs:
        if x.get("state") != "Booted":
            continue
        if x.get("name") == want:
            print(x["udid"])
            raise SystemExit
        if fallback is None and "iPhone" in x.get("name", ""):
            fallback = x["udid"]
if fallback:
    print(fallback)
'
)"
if [[ -z "${UDID:-}" ]]; then
  echo "error: no booted iPhone simulator" >&2
  exit 1
fi
echo "    UDID=$UDID"

echo "==> Building Debug → $DERIVED"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  -quiet \
  build

APP="$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -name 'TheScale.app' -maxdepth 2 | head -1)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: TheScale.app not found under $DERIVED" >&2
  exit 1
fi

xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100 \
  --operatorName "" >/dev/null 2>&1 || true

echo "==> Fresh install (promo mode from first launch — no permission sheets)"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP" >/dev/null
xcrun simctl privacy "$UDID" grant all "$BUNDLE_ID" >/dev/null 2>&1 || true

to_asc_size() {
  local src="$1"
  local dst="$2"
  sips -z "$ASC_H" "$ASC_W" "$src" --out "$dst" >/dev/null
}

capture_one() {
  local shot="$1"
  local out_name="$2"
  local raw="$OUT_DIR/raw/$out_name"
  local final="$OUT_DIR/$out_name"
  echo "  • -promoShot=$shot → $out_name"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  # ALWAYS pass promoShot so DemoHealthKitSeeder + notif auth never present sheets.
  xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    "$DEMO_FLAG" \
    "-promoShot=$shot" \
    >/dev/null
  sleep "$SETTLE_SECONDS"
  dismiss_system_sheets
  sleep 0.4
  xcrun simctl io "$UDID" screenshot --type=png "$raw"
  to_asc_size "$raw" "$final"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

echo "==> Capturing clean ASC 6.5\" set (${ASC_W}×${ASC_H})"
capture_one "home" "01-home.png"
capture_one "weigh" "02-weigh.png"
capture_one "progress" "03-progress.png"
capture_one "charts" "04-charts.png"
capture_one "keel" "05-coach.png"
capture_one "paywall-pro-annual" "06-paywall.png"
capture_one "meals" "07-meals.png"

xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true

echo "==> Wrote:"
for f in 01-home 02-weigh 03-progress 04-charts 05-coach 06-paywall 07-meals; do
  path="$OUT_DIR/$f.png"
  if [[ -f "$path" ]]; then
    dims="$(sips -g pixelWidth -g pixelHeight "$path" 2>/dev/null | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
    echo "  $f.png  $dims"
  fi
done
open -R "$OUT_DIR/01-home.png" >/dev/null 2>&1 || true
