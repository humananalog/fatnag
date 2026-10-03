#!/usr/bin/env bash
# Capture Unlock Coach paywall screenshots for App Store Connect Review Information.
# One PNG per Coach SKU (Apple X.99 prices: $1.99 / $19.99 / $7.99 / $79.99).
#
# Outputs under TheScale/docs/operations/asc-review-screenshots/:
#   review-plus-annual.png
#   review-plus-monthly.png
#   review-pro-annual.png
#   review-pro-monthly.png
#
# Usage:
#   ./TheScale/scripts/capture-asc-subscription-review.sh
#   DEVICE_NAME="iPhone 17 Pro" ./TheScale/scripts/capture-asc-subscription-review.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="$ROOT/TheScale/docs/operations/asc-review-screenshots"
SCHEME="${SCHEME:-TheScale}"
PROJECT="$ROOT/TheScale/TheScale.xcodeproj"
BUNDLE_ID="${BUNDLE_ID:-app.thescale.ios}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17}"
DERIVED="${DERIVED:-$ROOT/TheScale/build/asc-review-derived}"
SETTLE_SECONDS="${SETTLE_SECONDS:-4.0}"
if [[ -z "${DEMO_FLAG:-}" ]]; then
  DEMO_FLAG="-demoMale"
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: Xcode not found at $DEVELOPER_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/_t*.png "$OUT_DIR"/_probe.png

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

echo "==> Installing once"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP" >/dev/null
xcrun simctl privacy "$UDID" grant all "$BUNDLE_ID" >/dev/null 2>&1 || true

capture_one() {
  local shot="$1"
  local out_name="$2"
  local out="$OUT_DIR/$out_name"
  echo "  • -promoShot=$shot → $out_name"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    "$DEMO_FLAG" \
    "-promoShot=$shot" \
    >/dev/null
  sleep "$SETTLE_SECONDS"
  xcrun simctl io "$UDID" screenshot --type=png "$out"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

echo "==> Capturing four Review Information screenshots"
capture_one "paywall-plus-annual" "review-plus-annual.png"
capture_one "paywall-plus-monthly" "review-plus-monthly.png"
capture_one "paywall-pro-annual" "review-pro-annual.png"
capture_one "paywall-pro-monthly" "review-pro-monthly.png"

echo "==> Wrote:"
ls -la "$OUT_DIR"/review-*.png
echo "Upload matching PNG to each Coach SKU Review Information field."
open -R "$OUT_DIR/review-plus-annual.png" >/dev/null 2>&1 || true
