#!/usr/bin/env python3
"""Composite simulator screenshots into the WithFrame iPhone 16 Pro bezel.

Fills every pixel of the rounded screen hole (stretch-fit, no cover crop),
then overlays the bezel so Dynamic Island and metal edges sit on top.
"""
from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
FRAME = ROOT / "assets/device/iphone-16-pro-frame.png"
SIM = ROOT.parents[1] / "TheScale/docs/operations/asc-screenshots/iphone-6.5/simulator"
OUT = ROOT / "assets/shots"
FRAMED = OUT / "framed"

# Prefer dark simulator captures; fall back to full numbered shots when IMG set skips a screen.
SOURCES = {
    "01-home": SIM / "IMG_8305 2.PNG",  # home
    "02-weigh": SIM / "02-weigh.png",  # live weigh (IMG set has no weigh)
    "03-progress": SIM / "IMG_8306 2.PNG",  # progress
    "04-keel": SIM / "05-coach.png",  # coach / Keel with full tab bar
}

WEB_WIDTH = 700


def screen_hole(alpha: np.ndarray) -> np.ndarray:
    hole = alpha == 0
    h, w = hole.shape
    cy, cx = h // 2, w // 2
    if not hole[cy, cx]:
        raise SystemExit("frame center is not transparent — expected screen hole")
    vis = np.zeros_like(hole)
    q = deque([(cy, cx)])
    vis[cy, cx] = True
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and hole[ny, nx] and not vis[ny, nx]:
                vis[ny, nx] = True
                q.append((ny, nx))
    return vis


def compose(shot_path: Path, frame: Image.Image, hole: np.ndarray, out_full: Path, out_web: Path) -> None:
    fw, fh = frame.size
    ys, xs = np.where(hole)
    sx0, sy0 = int(xs.min()), int(ys.min())
    sw, sh = int(xs.max() - sx0 + 1), int(ys.max() - sy0 + 1)

    shot = Image.open(shot_path).convert("RGB")
    fitted = np.array(shot.resize((sw, sh), Image.Resampling.LANCZOS))

    # Full-canvas screen layer: only hole pixels get screenshot RGB + opaque alpha.
    layer = np.zeros((fh, fw, 4), dtype=np.uint8)
    layer[sy0 : sy0 + sh, sx0 : sx0 + sw, :3] = fitted
    layer[hole, 3] = 255

    out = Image.alpha_composite(Image.fromarray(layer, "RGBA"), frame)

    FRAMED.mkdir(parents=True, exist_ok=True)
    out.save(out_full, "PNG", optimize=True)
    web_h = round(fh * WEB_WIDTH / fw)
    web = out.resize((WEB_WIDTH, web_h), Image.Resampling.LANCZOS)
    web.save(out_web, "PNG", optimize=True)
    jpg_name = out_web.name.replace("-device.png", ".jpg")
    web.convert("RGB").save(out_web.with_name(jpg_name), quality=90, optimize=True)
    print(f"wrote {out_web.name} ({WEB_WIDTH}x{web_h}) from {shot_path.name}")


def main() -> None:
    frame = Image.open(FRAME).convert("RGBA")
    hole = screen_hole(np.array(frame)[:, :, 3])
    ys, xs = np.where(hole)
    print(
        "screen hole",
        int(xs.min()),
        int(ys.min()),
        int(xs.max() - xs.min() + 1),
        int(ys.max() - ys.min() + 1),
        "px",
        int(hole.sum()),
    )
    for key, src in SOURCES.items():
        if not src.exists():
            raise SystemExit(f"missing source: {src}")
        compose(src, frame, hole, FRAMED / f"{key}.png", OUT / f"{key}-device.png")


if __name__ == "__main__":
    main()
