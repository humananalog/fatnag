#!/usr/bin/env python3
"""Fail if any determinate ProgressView(value:…) reappears in TheScale sources.

Indeterminate ProgressView() / ProgressView("…") are allowed.
SwiftUI logs 'out-of-bounds progress value' for ProgressView(value:total:) when
spring / bad ratios leave 0...total — use ScaleBoundedProgress instead.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "TheScale"
PATTERN = re.compile(r"ProgressView\s*\(\s*value\s*:")


def main() -> int:
    hits: list[str] = []
    for path in ROOT.rglob("*.swift"):
        text = path.read_text(encoding="utf-8")
        for i, line in enumerate(text.splitlines(), 1):
            # Comments documenting the ban are fine.
            stripped = line.lstrip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            if PATTERN.search(line):
                hits.append(f"{path.relative_to(ROOT.parent)}:{i}: {line.strip()}")
    if hits:
        print("Determinate ProgressView(value:) found — use ScaleBoundedProgress:", file=sys.stderr)
        for h in hits:
            print(f"  {h}", file=sys.stderr)
        return 1
    print("OK: no determinate ProgressView(value:) in TheScale sources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
