# docs/renders/issue-87 — `--page-height` before/after captures

This directory holds the side-by-side capture diffs that satisfy issue #87
acceptance criterion 4 ("side-by-side capture diffs in docs/renders/ confirming
the full page is now visible").

The pairs are produced by the verification harness:

```bash
CARBONYL_BIN=/path/to/runtime-x11/carbonyl test/repro/issue-87/capture.sh
# then copy the chosen out/<host>/{before,after}.png pairs here
```

**Runtime requirement:** the captures must come from a `runtime-x11` built from
`main` at or after chromium patch 0029 (commit `2f49034`, "honor --viewport in
X11 ozone screen") **and** carrying PR #226 (`--page-height`). The
`build-runtime` CI on the post-#226 `main` produces that runtime. The bundled
`build/pre-built/...alpha.1` runtime predates 0029 and cannot demonstrate the fix.

**Host requirement:** the harness needs a host where carbonyl renders page *text*.
A GPU-less `Xvfb` with only the SwiftShader fallback paints the page background but
little text, so the captures come out near-empty for both before and after — use a
GL-capable host or the CI capture environment. The most direct full-raster check is
the screenshot-capture FFI (#3), exercised by the carbonyl-fleet screenshot harness.

See `test/repro/issue-87/README.md` for the full method and pass criterion.
