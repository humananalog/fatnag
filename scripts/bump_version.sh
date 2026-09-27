#!/usr/bin/env bash
# SOTA version control for TheScale / fatnag.
# Usage:
#   scripts/bump_version.sh              # patch +1 marketing, build +1
#   scripts/bump_version.sh 1.1.0        # set marketing, build +1
#   scripts/bump_version.sh 1.1.0 120    # set marketing + build explicitly
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBX="$ROOT/TheScale/TheScale.xcodeproj/project.pbxproj"

if [[ ! -f "$PBX" ]]; then
  echo "error: missing $PBX" >&2
  exit 1
fi

current_marketing="$(grep -m1 'MARKETING_VERSION =' "$PBX" | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/')"
current_build="$(grep -m1 'CURRENT_PROJECT_VERSION =' "$PBX" | sed -E 's/.*CURRENT_PROJECT_VERSION = ([^;]+);/\1/')"

if [[ $# -ge 1 ]]; then
  new_marketing="$1"
else
  IFS='.' read -r major minor patch <<<"$current_marketing"
  patch="${patch:-0}"
  new_marketing="${major}.${minor}.$((patch + 1))"
fi

if [[ $# -ge 2 ]]; then
  new_build="$2"
else
  new_build="$((current_build + 1))"
fi

tmp="$(mktemp)"
sed -E \
  -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${new_marketing};/g" \
  -e "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${new_build};/g" \
  "$PBX" >"$tmp"
mv "$tmp" "$PBX"

echo "bumped ${current_marketing} (${current_build}) → ${new_marketing} (${new_build})"
echo "file: $PBX"
