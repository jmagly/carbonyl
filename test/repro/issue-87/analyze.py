#!/usr/bin/env python3
"""Measure rastered extent of issue-87 before/after captures.

The X-mirror window maps at the screen origin and is exactly `window.browser`
tall (the CSS viewport) once chromium patch 0029 honours it. Everything below /
right of that window is X-root background. So the lowest screen row that still
belongs to the carbonyl window (= differs from the X-root background) is the
**rastered extent** — which equals the viewport height for `before` and rises to
`--page-height` (or the page's own content height, whichever Chromium rasters)
for `after`. That growth is exactly the #87 fix.

This is a rastered-extent proxy (it can't tell page content from page-background
fill inside the window); the human confirms actual below-the-fold *content* by
eyeballing the before/after PNGs that land in docs/renders/issue-87/.

Pass criterion: for each URL the `after` extent must materially exceed the
`before` extent (which caps near the viewport height). A page whose document
already fits the `before` viewport is a control and reported as `n/a`.

Usage: analyze.py <out_dir> <viewport_height>
Exit 0 if every measurable URL improves (or is a short/control page), else 1.
"""
import sys
from pathlib import Path

from PIL import Image


def rastered_extent(path: Path, win_width: int = 1280, bg_tol: int = 8) -> int:
    """Return the lowest screen row still inside the carbonyl X-mirror window.

    Background = the bottom-right corner, which is guaranteed X-root (the window
    is <= win_width wide and shorter than the screen). A row counts as "window"
    if any sampled pixel within the window's x-range differs from that background
    by more than bg_tol on a channel. Scans bottom-up and returns the first such
    row (the rastered extent in px).
    """
    img = Image.open(path).convert("RGB")
    w, h = img.size
    px = img.load()
    bg = px[w - 1, h - 1]  # X-root background, outside the window

    def differs(c) -> bool:
        return any(abs(c[i] - bg[i]) > bg_tol for i in range(3))

    x_max = min(w, win_width)
    xs = range(0, x_max, max(1, x_max // 256))
    for y in range(h - 1, -1, -1):
        for x in xs:
            if differs(px[x, y]):
                return y + 1
    return 0


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    out = Path(sys.argv[1])
    vp_h = int(sys.argv[2])

    rows = []
    failures = 0
    for d in sorted(p for p in out.iterdir() if p.is_dir()):
        before_p, after_p = d / "before.png", d / "after.png"
        if not (before_p.exists() and after_p.exists()):
            continue
        b_ext = rastered_extent(before_p)
        a_ext = rastered_extent(after_p)
        # "before" caps near the viewport height; treat a doc that fits within
        # ~viewport as a control (no below-the-fold content to reveal).
        control = b_ext <= vp_h + 40
        improved = a_ext > b_ext + 40
        if control and not improved:
            verdict = "n/a (short page / control)"
        elif improved:
            verdict = "PASS (full page rastered)"
        else:
            verdict = "FAIL (no extra content captured)"
            failures += 1
        rows.append((d.name, b_ext, a_ext, verdict))

    name_w = max((len(r[0]) for r in rows), default=4)
    print(f"\n{'url':<{name_w}}  {'before_px':>9}  {'after_px':>8}  verdict")
    print("-" * (name_w + 34))
    for name, b, a, verdict in rows:
        print(f"{name:<{name_w}}  {b:>9}  {a:>8}  {verdict}")

    if not rows:
        print("\nNo before/after pairs found — did capture.sh run?")
        return 1
    print(f"\n{'FAIL' if failures else 'PASS'}: {failures} regression(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
