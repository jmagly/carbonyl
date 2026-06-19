# Verification harness — issue #87 (`--page-height` full-page capture)

> "Full-page content still not visible — only the first screenful (above-the-fold)
> of a page reaches the capture."

This harness proves that `--page-height=N` makes Chromium lay out **and raster**
the full page, so the X-mirror / framebuffer / screenshot capture sees
below-the-fold content instead of only the top viewport.

## What #87 was

A viewport of `1280x800` lays the page out against an 800px-tall window, so
Chromium never rasters anything below row 800. The terminal renderer additionally
only samples the top-left `cells*(2,4)` window — but that is a *separate* clip.
This issue is specifically the **capture** path (automation / screenshot / X-mirror
/ framebuffer): even with a large terminal, the *rastered* page is only viewport-tall.

## The fix

`--page-height=N` (or `CARBONYL_PAGE_HEIGHT=N`) overrides **only** the CSS-viewport
height (`window.browser.height`, see `src/output/window.rs`). Width is preserved
from `--viewport` or the terminal-derived width. Chromium then lays out and rasters
the page `N` px tall; the X-mirror window (`x_mirror.cc`) and the screenshot-capture
FFI (`carbonyl_set_screenshot_capture` / `draw_bitmap`, #3) both carry the full-height
raster. Pure-Rust, ABI-neutral. See PR #226.

## Runtime requirement (important)

X-mirror capture of the viewport height depends on **chromium patch 0029**
("honor --viewport in X11 ozone screen", commit `2f49034`, 2026-05-22): without it,
`X11ScreenOzone` ignores the viewport and the carbonyl X window takes the screen
size instead. So this harness must run against a runtime built from `main` **at or
after 2f49034** *and* carrying PR #226 (`--page-height`). The `runtime-x11-<hash>`
artifact published by `build-runtime` on the post-#226 `main` is the correct target.
The pre-bundled `build/pre-built/...alpha.1` runtime is **too old** (predates 0029)
and will NOT demonstrate the fix.

## Requirements

- `Xvfb` (tall virtual screen), `ffmpeg` (x11grab — used instead of `scrot`),
  `python3` + Pillow (PIL) for the content-extent measurement.
- An **x11-capable** carbonyl runtime as above. Point `CARBONYL_BIN` at it (the
  directory must also contain `libcarbonyl.so`, `icudtl.dat`, the `.so`/`.bin`
  blobs, and `locales/`).

## Run

```bash
CARBONYL_BIN=/path/to/runtime-x11/carbonyl ./capture.sh
```

`capture.sh` starts a `1280x4200` Xvfb, then for each test URL captures two frames:

| Frame | Flags | Expected rastered height |
|-------|-------|--------------------------|
| `before` | `--viewport=1280x800` | ~800 px (above-the-fold only) |
| `after`  | `--viewport=1280x800 --page-height=4000` | up to 4000 px (full page) |

Captures land in `out/<host>/{before,after}.png`. `analyze.py` then reports, per URL,
the lowest image row that still contains non-background content (the "content extent").

## Pass criterion

For each URL whose document is taller than 800 px, the **after** content extent must
be materially greater than the **before** extent (which caps near ~800 px). Pages
shorter than 800 px (e.g. a bare `example.com`) are expected to be ~equal and are
reported as `n/a` rather than failures.

## Test URLs (from #74 / #87)

- https://example.com (short — control, expect ~equal)
- https://news.ycombinator.com
- https://en.wikipedia.org/wiki/Headless_browser
- https://github.com/jmagly/carbonyl

## Provenance

The `before`/`after` PNGs that satisfy issue #87 acceptance criterion 4
("side-by-side capture diffs in `docs/renders/`") are produced by running this
harness against the post-#226 `runtime-x11` and copying the chosen pairs into
`docs/renders/issue-87/`.
