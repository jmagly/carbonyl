#!/usr/bin/env python3
"""Measure rendered-content extent of issue-87 before/after captures.

capture.sh drives carbonyl under a large PTY so the X-mirror window is
`cells*(2,4)` = full-screen, and blits Chromium's compositor frame into it. With
`--viewport=1280x800` the frame is 800px tall (content only in the top band);
with `--page-height=4000` the frame is up to 4000px tall (content down the page).

We measure the lowest 200px band that still holds rendered text (pixels darker
than a light page bg), which rises from ~viewport height (before) to the full
page (after). That growth is the #87 fix.

REQUIRES a host where carbonyl actually renders page text. Under a GPU-less Xvfb
with only the SwiftShader fallback, carbonyl may paint the page background but
little text, yielding near-empty bands for both before and after — that is an
environment limitation, not a fix regression. Run on a GL-capable host (or the
CI capture environment).

Pass criterion: for each URL the `after` extent must materially exceed the
`before` extent (which caps near the viewport height). A page whose document
already fits the `before` viewport is a control and reported as `n/a`.

Usage: analyze.py <out_dir> <viewport_height>
Exit 0 if every measurable URL improves (or is a short/control page), else 1.
"""
import sys
from pathlib import Path

from PIL import Image


def rastered_extent(path: Path, win_width: int = 1270, band: int = 200,
                    min_text: int = 40) -> int:
    """Return the lowest px row that still contains rendered page *content*.

    The carbonyl X-mirror window paints the page background across its whole
    height, so a background-vs-corner test can't tell rastered content from a
    plain bg fill. Instead we count "text" pixels (notably darker than a light
    page bg: channel sum < 480, i.e. avg < 160) per 200px band, and return the
    bottom of the lowest band that exceeds `min_text` text pixels. That tracks
    where actual rendered content ends, which rises from ~viewport height
    (before) to the full page (after).
    """
    img = Image.open(path).convert("RGB")
    w, h = img.size
    px = img.load()
    x_max = min(w, win_width)
    last = 0
    for b0 in range(0, h, band):
        cnt = 0
        for y in range(b0, min(b0 + band, h), 4):
            for x in range(0, x_max, 6):
                r, g, bl = px[x, y]
                if r + g + bl < 480:
                    cnt += 1
        if cnt > min_text:
            last = min(b0 + band, h)
    return last


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
