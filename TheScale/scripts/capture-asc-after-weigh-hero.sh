#!/usr/bin/env bash
# Capture ASC-ready after-weigh (black roast) hero cards for male + female.
#
# Output:
#   TheScale/docs/operations/asc-screenshots/iphone-6.5/after-weigh-male.png
#   TheScale/docs/operations/asc-screenshots/iphone-6.5/after-weigh-female.png
#
# Usage:
#   ./TheScale/scripts/capture-asc-after-weigh-hero.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="$ROOT/TheScale/docs/operations/asc-screenshots/iphone-6.5"
SCHEME="${SCHEME:-TheScale}"
PROJECT="$ROOT/TheScale/TheScale.xcodeproj"
BUNDLE_ID="${BUNDLE_ID:-app.thescale.ios}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17}"
DERIVED="${DERIVED:-$ROOT/TheScale/build/asc-hero-derived}"
SETTLE_SECONDS="${SETTLE_SECONDS:-4.5}"
ASC_W=1284
ASC_H=2778

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: Xcode not found at $DEVELOPER_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR/raw"

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

echo "==> Fresh install"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP" >/dev/null
xcrun simctl privacy "$UDID" grant all "$BUNDLE_ID" >/dev/null 2>&1 || true

to_asc_size() {
  local src="$1"
  local dst="$2"
  sips -z "$ASC_H" "$ASC_W" "$src" --out "$dst" >/dev/null
}

capture_hero() {
  local demo_flag="$1"
  local shot="$2"
  local out_name="$3"
  local raw="$OUT_DIR/raw/$out_name"
  local final="$OUT_DIR/$out_name"
  echo "  • $demo_flag -promoShot=$shot → $out_name"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    "$demo_flag" \
    "-promoShot=$shot" \
    >/dev/null
  sleep "$SETTLE_SECONDS"
  xcrun simctl io "$UDID" screenshot --type=png "$raw"
  to_asc_size "$raw" "$final"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

echo "==> Capturing after-weigh heroes (${ASC_W}×${ASC_H})"
capture_hero "-demoMale" "after-weigh" "after-weigh-male.png"
capture_hero "-demoFemale" "after-weigh" "after-weigh-female.png"
capture_hero "-demoMale" "after-weigh-win" "after-weigh-win-male.png"
capture_hero "-demoFemale" "after-weigh-win" "after-weigh-win-female.png"

xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true

echo "==> Wrote:"
for f in after-weigh-male after-weigh-female after-weigh-win-male after-weigh-win-female; do
  path="$OUT_DIR/$f.png"
  if [[ -f "$path" ]]; then
    dims="$(sips -g pixelWidth -g pixelHeight "$path" 2>/dev/null | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
    echo "  $f.png  $dims"
  fi
done
open -R "$OUT_DIR/after-weigh-win-male.png" >/dev/null 2>&1 || true
