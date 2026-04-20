# Phase 0 W0.1 — Patch Paper-Audit for x11 Ozone Compatibility

**Audit date**: 2026-04-20
**Audited tree**: `/srv/vmshare/dev-inbox/carbonyl/carbonyl` (Chromium M147 + Carbonyl patches 0001–0024)
**Audit scope**: predict which of the 24 Carbonyl patches will fail or need revision when building with `ozone_platform="x11"` instead of `ozone_platform="headless"`
**Gate**: informs risk assessment for `roctinam/carbonyl#57` (W0.2 x11 build) before committing to the 1–3h Chromium rebuild

## Executive summary

**Prediction: PASS with 1–2 runtime triage passes, not a revise-N-patches effort.**

The audit uncovered a critical framing correction that significantly reduces Phase 0 risk: the 24 patches do not depend on the `ozone_platform=headless` **Ozone windowing backend** — they depend on Chromium's separate `chromium/src/headless/` **shell** (`headless_browser_impl`, `headless_shell`, `HeadlessScreen`, etc.). These are two different layers that are often confused because they share the word "headless":

| Concern | Layer | Chromium path | Affected by `ozone_platform` switch? |
|---------|-------|---------------|:------------------------------------:|
| Headless **shell** | High-level product | `chromium/src/headless/` | **No** — shell is Ozone-agnostic |
| Headless **Ozone platform** | Windowing/input backend | `chromium/src/ui/ozone/platform/headless/` | **Yes** — this is what x11 replaces |

**No patch in the set touches `ui/ozone/platform/headless/`**. Carbonyl's patches all target the shell plus cross-cutting viz/compositor/Blink code. Switching `ozone_platform` from `headless` to `x11` therefore does not affect the files the patches modify. All 24 should apply cleanly at the file-level.

**Remaining risk is semantic, not file-level**: patches `0003`, `0009`, `0013` hook Chromium's viz/compositor output into Carbonyl's bridge. With `ozone_platform=x11`, Chromium additionally has an X display to render to. We need to verify the bridge still intercepts correctly and the X-side capture path works alongside the terminal render.

This outcome was not predicted before the audit — ADR-002 rev 2's risk language overstated patch-revision cost. The audit de-risks Phase 0 substantially.

## Categorization

All 24 patches are classified **green** for file-apply risk. The `headless` references in each patch are to the shell, not the Ozone platform. A subset remain **yellow** for semantic risk (to be validated in W0.2 runtime).

| Patch | File-apply | Semantic | Notes |
|-------|:----------:|:--------:|-------|
| `0001-Add-Carbonyl-library` | Green | Green | Adds `carbonyl/build` + `carbonyl/src` + `headless/BUILD.gn` (shell build file). Orthogonal to Ozone. |
| `0002-Add-Carbonyl-service` | Green | Green | 0 headless refs. Mojo service addition. |
| `0003-Setup-shared-software-rendering-surface` | Green | **Yellow** | Touches `components/viz/` + `content/browser/compositor/` + `ui/compositor/compositor.h`. Hooks the shared software surface. With x11 Ozone, Chromium has an X window in addition to the shared surface — need to verify both paths route correctly. |
| `0004-Setup-browser-default-settings` | Green | Green | Modifies `headless/lib/browser/headless_browser_impl.cc` (shell) + `headless/public/headless_browser.h`. Pure shell config (user agent, window size defaults). Ozone-agnostic. |
| `0005-Remove-some-debug-assertions` | Green | Green | Modifies Blink files. The one `headless` reference is commentary. |
| `0006-Setup-display-DPI` | Green | **Yellow** | Modifies `headless/lib/browser/headless_platform_delegate_aura.cc` + `headless_screen.cc` + `ui/display/display.cc`. `HeadlessScreen` is the shell's screen object — still used with any Ozone platform. Verify DPI values are consistent when Chromium also has an X display with its own DPI. |
| `0007-Disable-text-effects` | Green | Green | 0 headless refs. Blink text rendering tweak. |
| `0008-Fix-text-layout` | Green | Green | 0 headless refs. Blink font layout. |
| `0009-Bridge-browser-into-Carbonyl-library` | Green | **Yellow** | The big shell-integration patch (681 lines). Touches `headless/app/*` + `headless/lib/browser/*`. No Ozone-platform dependency in the modified paths. Main semantic question: does the shell's main loop initialize correctly when Ozone is `x11`? Expected yes — headless shell is designed to work with any Ozone. |
| `0010-Conditionally-enable-text-rendering` | Green | Green | 0 headless refs. |
| `0011-Rename-carbonyl-Renderer-to-carbonyl-Bridge` | Green | Green | Pure rename across shell files. Mechanical. |
| `0012-Create-separate-bridge-for-Blink` | Green | Green | 0 headless refs. |
| `0013-Refactor-rendering-bridge` | Green | **Yellow** | Largest patch (979 lines). Touches `content/browser/`, `content/renderer/`, `components/viz/service/`, `headless/`, plus Blink. Hooks Carbonyl bridge into the rendering pipeline. **This is the single highest-risk patch under x11**: it assumes Chromium's output goes through the `SoftwareOutputDeviceProxy` into Carbonyl's bridge. With `ozone_platform=x11`, Chromium may route differently. Runtime validation required. |
| `0014-Move-Skia-text-rendering-control-to-bridge` | Green | Green | 0 headless refs. |
| `0015-0017` (build + viz compat fixes) | Green | Green | 0 headless refs each. |
| `0018-fix-m120-fix-compile-errors-in-render_frame_impl-and` | Green | Green | 15 refs — all pointing to `headless/lib/browser/headless_browser_impl.{cc,h}` forward declarations. Shell-level. |
| `0019-0022` (m120/m135 compile fixes) | Green | Green | 0 headless refs each. |
| `0023-fix-m135-Path-B-build-fixes-disable-b64-text-capture` | Green | **Yellow** | Extends `0013`. Modifies `software_output_device_proxy.cc`, `render_frame_impl.cc`, `headless_screen.{cc,h}`, plus Blink. Same semantic concern as `0013`: the rendering bridge may behave differently when an X display is in play. |
| `0024-fix-chromium-Path-A-allow-carbonyl-src-blink-to-depe` | Green | Green | 0 headless refs. Blink dependency graph. |

**Summary counts:**
- File-apply green: **24 / 24** (100%)
- Semantic green: **19 / 24**
- Semantic yellow (need runtime validation): **5 / 24** — `0003`, `0006`, `0009`, `0013`, `0023`
- Red (fundamentally incompatible): **0 / 24**

## Verification used

1. `grep -l` for headless-related strings against all 24 patch files — identified 10 patches with refs
2. `grep "^+++ b/"` on each at-risk patch — extracted every file each patch modifies
3. `grep -l "ui/ozone/platform/headless"` against all 24 patches — **zero hits**, confirming no patch touches the Ozone backend
4. `grep -l "ui/ozone/platform/x11"` against all 24 patches — **zero hits**, confirming no untangling needed
5. `ls chromium/src/ui/ozone/platform/x11/` — confirmed the x11 Ozone platform source is present and buildable in the Carbonyl tree
6. Spot-read of patch `0004` confirmed "headless" refers to the shell (paths: `headless/lib/browser/`, `headless/public/`)

## Risk register (carries into `#57` rebuild)

Five yellow patches to runtime-validate:

| Patch | Risk | Validation strategy in `#57` |
|-------|------|------------------------------|
| `0003` | Shared software surface may not intercept when Chromium has an X window | Load a test page in the x11-Ozone build; inspect whether frame data reaches Carbonyl's `host_display_client` path — log or assert on `OnPaint`/`DrawToBitmap` invocation count |
| `0006` | Display DPI routing — Chromium's `ui::Display` may prefer x11's reported DPI over `HeadlessScreen`'s override | Dump `display.device_scale_factor()` at startup and verify it matches Carbonyl's `CARBONYL_DPI` env override |
| `0009` | Shell main loop may initialize differently with a real Ozone platform | `headless_shell` startup logs; ensure `Carbonyl::Bridge` gets wired and `carbonyl_bridge_main()` is reached |
| `0013` | Rendering bridge (`SoftwareOutputDeviceProxy`) may be bypassed in favor of x11 native output | Frame-by-frame: compare bridge-side frame count to X-side frame count while rendering a known page. Both should be non-zero and reasonably close. |
| `0023` | Same as `0013` — these two are a pair (`0023` fixes `0013` for m135) | Covered by `0013`'s validation |

## Recommended execution order (update to `#57`)

1. Switch `ozone_platform` to `"x11"` in `src/browser/args.gn` (or equivalent)
2. Apply full patch set 0001–0024 with `scripts/patches.sh apply`. Expect clean apply. If any patch rejects at the file level, treat as a bug in this audit and file a correction.
3. `autoninja -C out/Default carbonyl` — compile. Most likely result: builds. If it fails, the failures will be compile-time (symbol/type/API) not patch-reject.
4. Launch Carbonyl against a known static HTML page. Three runtime checks in order:
   a. Does the shell start (0009)? Bridge wired (0011)?
   b. Do frames reach the Carbonyl bridge (0003, 0013, 0023)?
   c. Is DPI reported correctly (0006)?
5. If (a) and (b) pass, proceed to W0.3/W0.4/W0.5/W0.6. If (b) fails, the rendering bridge needs patching; Phase 0 extends into that triage.

## What this does NOT tell us

- **Compile errors are not predicted.** The audit validates paths-touched, not symbol-level API compatibility. Patches may reference Chromium internals that differ between Ozone platforms (rare but possible). Only `#57`'s actual compile tells us.
- **Runtime frame-delivery behavior is not predicted.** The yellow patches could all work as-is, could need minor adjustment, or could require significant rework. This audit says "plausibly works" not "definitely works."
- **Performance parity is not assessed.** Rendering speed with an active X display vs. headless-only may differ. Out of scope for this audit; relevant to `#62` (text-render parity) and potentially a post-Phase-0 perf spike.

## Correction for ADR-002 rev 2

The phrase "Carbonyl's existing patches (0001–0024) target `headless`; some may need rework" in ADR-002 rev 2 should be revised to:

> Carbonyl's patches target the **headless Chromium shell** (`chromium/src/headless/`), not the headless Ozone backend. Switching `ozone_platform` from `headless` to `x11` therefore does not invalidate the patches at the file level. A subset (0003, 0006, 0009, 0013, 0023) hook into the rendering bridge and need runtime validation to confirm they still route correctly when Chromium has an X display in addition to the bridge.

Follow-up action: amend ADR-002 rev 2 accordingly, or note the correction in `#57` when it kicks off.

## Audit procedure — for reproducibility

```bash
cd /srv/vmshare/dev-inbox/carbonyl/carbonyl

# Step 1 — patches with headless references
grep -l -iE "headless|OzoneHeadless" chromium/patches/chromium/*.patch

# Step 2 — per-patch ref count
for p in chromium/patches/chromium/*.patch; do
  hits=$(grep -c -iE "headless|OzoneHeadless" "$p")
  total=$(wc -l < "$p")
  printf "%-70s %3d refs / %4d lines\n" "$(basename "$p")" "$hits" "$total"
done

# Step 3 — files touched per at-risk patch
for p in chromium/patches/chromium/{0001,0003,0004,0005,0006,0009,0011,0013,0018,0023}*.patch; do
  echo "=== $(basename $p) ==="
  grep "^+++ b/" "$p" | sed 's|^+++ b/||'
done

# Step 4 — critical distinction check
grep -l "ui/ozone/platform/headless" chromium/patches/chromium/*.patch   # should be empty
grep -l "ui/ozone/platform/x11"      chromium/patches/chromium/*.patch   # should be empty

# Step 5 — confirm x11 Ozone source present
ls chromium/src/ui/ozone/platform/x11/ | head
```

Audit complete.
