#!/usr/bin/env bash
# Capture Bob/Alice promo screenshots (and optional recordings) from the iOS Simulator
# into sites/fatnag-com/assets/shots/ for the marketing placeholders.
#
# Usage:
#   ./sites/fatnag-com/scripts/capture-promo-shots.sh
#   ./sites/fatnag-com/scripts/capture-promo-shots.sh --record
#   DEVICE_NAME="iPhone 17" ./sites/fatnag-com/scripts/capture-promo-shots.sh
#
# Requires full Xcode + a Debug build of TheScale (demo + promoShot flags are DEBUG-only).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SITE="$ROOT/sites/fatnag-com"
SHOTS="$SITE/assets/shots"
SCHEME="${SCHEME:-TheScale}"
PROJECT="$ROOT/TheScale/TheScale.xcodeproj"
BUNDLE_ID="${BUNDLE_ID:-app.thescale.ios}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17}"
DERIVED="${DERIVED:-$ROOT/TheScale/build/promo-derived}"
SETTLE_SECONDS="${SETTLE_SECONDS:-4.0}"
DO_RECORD=0

for arg in "$@"; do
  case "$arg" in
    --record|-r) DO_RECORD=1 ;;
    --help|-h)
      sed -n '1,20p' "$0"
      exit 0
      ;;
  esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: Xcode not found at $DEVELOPER_DIR" >&2
  exit 1
fi

mkdir -p "$SHOTS/bob" "$SHOTS/alice" "$SHOTS/recordings"

echo "==> Booting simulator: $DEVICE_NAME"
xcrun simctl boot "$DEVICE_NAME" 2>/dev/null || true
if [[ -d "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" ]]; then
  open -a "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" >/dev/null 2>&1 || true
fi
sleep 1

UDID="$(xcrun simctl list devices booted -j | python3 -c '
import json,sys
d=json.load(sys.stdin)
want="'"$DEVICE_NAME"'"
fallback=None
for _runtime,devs in d.get("devices",{}).items():
  for x in devs:
    if x.get("state")!="Booted":
      continue
    if x.get("name")==want:
      print(x["udid"]); raise SystemExit
    if fallback is None and "iPhone" in x.get("name",""):
      fallback=x["udid"]
if fallback:
  print(fallback)
')"
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
echo "    APP=$APP"

xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100 \
  --operatorName "" >/dev/null 2>&1 || true

capture_shot() {
  local persona="$1"
  local demo_flag="$2"
  local shot="$3"
  local out_name="$4"
  local out="$SHOTS/$persona/$out_name"

  echo "  • $persona / $shot → $out_name"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP" >/dev/null
  xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    "$demo_flag" \
    "-promoShot=$shot" \
    >/dev/null
  sleep "$SETTLE_SECONDS"
  xcrun simctl io "$UDID" screenshot --type=png "$out"
  if command -v cwebp >/dev/null 2>&1; then
    cwebp -quiet -q 82 "$out" -o "${out%.png}.webp" || true
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

record_persona() {
  local persona="$1"
  local demo_flag="$2"
  local out="$SHOTS/recordings/$persona-tour.mp4"
  echo "  • recording $persona → $(basename "$out")"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP" >/dev/null
  rm -f "$out"
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$out" &
  local rec_pid=$!
  sleep 1
  for shot in home weigh progress keel; do
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" "$demo_flag" "-promoShot=$shot" >/dev/null
    sleep 2.6
  done
  sleep 0.5
  kill -INT "$rec_pid" >/dev/null 2>&1 || true
  wait "$rec_pid" 2>/dev/null || true
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

SHOTS_LIST=(
  "home:01-home.png"
  "weigh:02-weigh.png"
  "progress:03-progress.png"
  "keel:04-keel.png"
)

echo "==> Capturing Bob (male)"
for entry in "${SHOTS_LIST[@]}"; do
  IFS=: read -r shot file <<<"$entry"
  capture_shot bob -demoMale "$shot" "$file"
done

echo "==> Capturing Alice (female)"
for entry in "${SHOTS_LIST[@]}"; do
  IFS=: read -r shot file <<<"$entry"
  capture_shot alice -demoFemale "$shot" "$file"
done

echo "==> Publishing Bob shots as site defaults"
for entry in "${SHOTS_LIST[@]}"; do
  IFS=: read -r _ file <<<"$entry"
  cp -f "$SHOTS/bob/$file" "$SHOTS/$file"
  if [[ -f "$SHOTS/bob/${file%.png}.webp" ]]; then
    cp -f "$SHOTS/bob/${file%.png}.webp" "$SHOTS/${file%.png}.webp"
  fi
done

if [[ "$DO_RECORD" -eq 1 ]]; then
  echo "==> Recordings"
  record_persona bob -demoMale
  record_persona alice -demoFemale
fi

xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true

echo "==> Done"
ls -la "$SHOTS"/*.png "$SHOTS/bob"/*.png "$SHOTS/alice"/*.png 2>/dev/null | sed 's|^|  |'
if [[ "$DO_RECORD" -eq 1 ]]; then
  ls -la "$SHOTS/recordings"/*.mp4 2>/dev/null | sed 's|^|  |' || true
fi
echo
echo "Next: open $SITE/index.html — placeholders resolve to /assets/shots/0N-*.png"
