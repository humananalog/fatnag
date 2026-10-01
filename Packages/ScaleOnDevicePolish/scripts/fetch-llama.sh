#!/usr/bin/env bash
# Downloads ggml llama XCFramework into Vendor/ (gitignored).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/llama.xcframework"
URL="https://github.com/ggml-org/llama.cpp/releases/download/b5046/llama-b5046-xcframework.zip"
CHECKSUM="c19be78b5f00d8d29a25da41042cb7afa094cbf6280a225abe614b03b20029ab"

if [[ -d "$DEST/ios-arm64" ]]; then
  echo "Already present: $DEST"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ZIP="$TMP/llama.zip"
echo "Downloading $URL …"
curl -fL --retry 3 -o "$ZIP" "$URL"
ACTUAL="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
if [[ "$ACTUAL" != "$CHECKSUM" ]]; then
  echo "Checksum mismatch: expected $CHECKSUM got $ACTUAL" >&2
  exit 1
fi
mkdir -p "$ROOT/Vendor"
rm -rf "$DEST"
unzip -q "$ZIP" -d "$TMP/out"
# Zip root is llama.xcframework
FOUND="$(find "$TMP/out" -maxdepth 2 -type d -name 'llama.xcframework' | head -1)"
if [[ -z "$FOUND" ]]; then
  echo "llama.xcframework missing from zip" >&2
  exit 1
fi
mv "$FOUND" "$DEST"
echo "Installed $DEST ($(du -sh "$DEST" | awk '{print $1}'))"
