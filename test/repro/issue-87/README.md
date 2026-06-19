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

## How the capture works (and why a large PTY)

The X-mirror window is `cells*(2,4)` px — i.e. it tracks the **terminal** size,
not the viewport. With the default ~80x24 cells the window is only ~160x92 px, so
it cannot show the full page no matter what `--page-height` is. `capture.sh`
therefore launches carbonyl through `ptycap.py`, which forces a **640x1001 PTY
winsize** → a **1280x4000** X-mirror window. Chromium's compositor frame is sized
to `window.browser` (the CSS viewport), so:

- `before` (`--viewport=1280x800`): frame is 800px tall → fills the top 800px.
- `after` (`--page-height=4000`): frame is up to 4000px tall → fills the window.

The PTY is also what lets carbonyl set up its terminal at all — without it the
bridge aborts (`Failed to setup terminal`) and never applies the viewport.

> The most *direct* full-raster path is the **screenshot capture FFI**
> (`carbonyl_set_screenshot_capture` + `carbonyl_capture_screenshot`, #3), which
> retains the entire compositor frame regardless of terminal size. That path is
> SDK-driven (no CLI trigger), so the carbonyl-fleet screenshot harness is the
> canonical place to assert full-page pixels. This X-mirror harness is the
> CLI-only approximation.

## Requirements

- `Xvfb`, `ffmpeg` (x11grab — used instead of `scrot`), `python3` + Pillow.
- An **x11-capable** post-#226 runtime carrying patch 0029 (see above).
  Point `CARBONYL_BIN` at it (its directory must hold `libcarbonyl.so`,
  `icudtl.dat`, the `.so`/`.bin` blobs, and `locales/`).
- **A host where carbonyl renders page text.** Under a GPU-less `Xvfb` with only
  the SwiftShader fallback, carbonyl may paint the page background but little/no
  text — yielding near-empty captures for **both** before and after. That is an
  environment limitation, not a fix regression. Use a GL-capable host or the CI
  capture environment.

## Run

```bash
CARBONYL_BIN=/path/to/runtime-x11/carbonyl ./capture.sh
```

Captures land in `out/<host>/{before,after}.png`. `analyze.py` reports, per URL,
the lowest 200px band that still holds rendered text (the content extent), and
asserts `after > before` for pages taller than the viewport.

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
