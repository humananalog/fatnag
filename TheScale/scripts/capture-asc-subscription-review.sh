#!/usr/bin/env bash
# Capture Unlock Coach paywall for App Store Connect → Subscription → Review Information.
#
# Output (reuse the same PNG on all four Coach SKUs):
#   TheScale/docs/operations/asc-review-screenshots/subscription-review-paywall-annual.png
#
# Usage:
#   ./TheScale/scripts/capture-asc-subscription-review.sh
#   DEVICE_NAME="iPhone 17 Pro" ./TheScale/scripts/capture-asc-subscription-review.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="$ROOT/TheScale/docs/operations/asc-review-screenshots"
OUT="$OUT_DIR/subscription-review-paywall-annual.png"
SCHEME="${SCHEME:-TheScale}"
PROJECT="$ROOT/TheScale/TheScale.xcodeproj"
BUNDLE_ID="${BUNDLE_ID:-app.thescale.ios}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17}"
DERIVED="${DERIVED:-$ROOT/TheScale/build/asc-review-derived}"
SETTLE_SECONDS="${SETTLE_SECONDS:-3.2}"
# Must match DemoPersonaSeeder (-demoMale / -demoFemale), not a marketing name.
if [[ -z "${DEMO_FLAG:-}" ]]; then
  DEMO_FLAG="-demoMale"
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: Xcode not found at $DEVELOPER_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/_probe.png"

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

echo "==> Installing + launching paywall promo shot ($DEMO_FLAG -promoShot=paywall)"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP" >/dev/null
xcrun simctl privacy "$UDID" grant all "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" \
  "$DEMO_FLAG" \
  "-promoShot=paywall" \
  >/dev/null

sleep "$SETTLE_SECONDS"
xcrun simctl io "$UDID" screenshot --type=png "$OUT"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "==> Wrote $OUT"
echo "Upload this same PNG to Review Information on all four Coach subscriptions."
open -R "$OUT" >/dev/null 2>&1 || true
