# Chromium Upgrade Plan: M111 → M135

**Current version:** `111.0.5511.1` (February 2023)
**Target version:** M135 (latest stable, early 2026)
**Milestone gap:** ~24 milestones
**Estimated effort:** 4–6 weeks, one engineer

---

## Background

Carbonyl is a fork of [fathyb/carbonyl](https://github.com/fathyb/carbonyl), which has been
inactive since February 2023. Its embedded Chromium is pinned at M111, which is now ~36 months
behind the current stable release. This exposes the project to unpatched CVEs and means it cannot
run modern web content correctly. This document is the engineering plan for the upgrade.

---

## Scope of Changes

Carbonyl embeds Chromium via 17 patches across three repositories:

| Repo | Patches | Summary |
|------|---------|---------|
| Chromium | 14 | Mojo service, display bridge, headless API hooks, text rendering control |
| Skia | 2 | Disable text rendering hook, export private APIs |
| WebRTC | 1 | Disable GIO on Linux |

The upgrade is not a simple version bump. Patch rebase is required because Carbonyl reaches into
Chromium internals (Viz compositor, Mojo registration, headless browser API, Blink text pipeline,
and Skia device internals) that changed significantly over 24+ milestones.

---

## Risk Assessment by Patch

### CRITICAL — Cannot compile without resolving

| Patch | Problem | Required action |
|-------|---------|----------------|
| **chromium/0007** `Disable-text-effects.patch` | Patches `ng_text_painter_base.cc`, which was merged into `text_painter_base.cc` around M120 and no longer exists as a separate file | Re-target the patch to `text_painter_base.cc`; verify the relevant method signature still exists |
| **chromium/0013** `Refactor-rendering-bridge.patch` | Creates `software_output_device_proxy.cc` as a new file that bridges shared-memory software rendering. The upstream file it shadowed was removed when display_embedder was refactored. The proxy abstraction no longer exists in the upstream tree | Full rewrite anchored to `software_output_device_ozone.cc` — the current Linux headless software output path |
| **args.gn** `enable_ppapi = false` | PPAPI was fully removed from Chromium; the GN arg no longer exists and will cause `gn gen` to fail with "Build argument has no effect" | Remove from `src/browser/args.gn` before attempting any build |

### HIGH — Significant rebase effort expected

| Patch | Problem |
|-------|---------|
| **chromium/0002** `Add-Carbonyl-service.patch` | Registers Mojo service in `browser_interface_binders.cc`, which underwent a multi-part "PopulateFrameBinders" refactoring. File structure changed significantly. |
| **chromium/0003** `Setup-shared-software-rendering-surface.patch` | Touches Viz Mojo interfaces (`display_private.mojom`, `layered_window_updater.mojom`). `CompositorFrameSinkType` enum was removed (~M136), `SubmitCompositorFrameSync()` removed (~M136), `OnBeginFrameAcks` removed (~M135). |
| **chromium/0008** `Fix-text-layout.patch` | Patches `style_resolver.cc`. StyleResolver is heavily committed; context lines will have significant drift. |
| **chromium/0009** `Bridge-browser-into-Carbonyl-library.patch` | Patches `headless_browser_impl.*` and `headless_web_contents_impl.*`. `HeadlessWebContents::Observer` was removed (~M125), window state changed from string to `enum class` (~M126), multiple headless public API changes throughout M112–M125. |
| **chromium/0010** `Conditionally-enable-text-rendering.patch` | Patches `render_frame_impl.cc` (zoom API changes, WebString renames), `style_resolver.cc` (same drift as 0008), and `platform/fonts/font.cc` (CanvasTextNG changes). |
| **chromium/0012** `Create-separate-bridge-for-Blink.patch` | Patches same files as 0010; same risks. |

### MEDIUM — Rebase expected but straightforward

| Patch | Problem |
|-------|---------|
| **chromium/0004** `Setup-browser-default-settings.patch` | `HeadlessBrowser::Options::Builder` class was removed (~M120). Config passing changed. |
| **chromium/0006** `Setup-display-DPI.patch` | Screen info moved to `//components` (~M127); `headless_screen.cc` context will have drifted. |
| **chromium/0014** `Move-Skia-text-rendering-control.patch` | Patches `render_frame_impl.cc` (drift from same file as 0010) and `skia/BUILD.gn` (may have changed). |
| **skia/0001** `Disable-text-rendering.patch` | `SkBitmapDevice.cpp` still exists; `LOOP_TILER` macro is an implementation detail that may have changed. |
| **skia/0002** `Export-some-private-APIs.patch` | Skia Ganesh headers moved to new paths (~M138); all `src/core/` include paths need verification. |

### LOW — Likely mechanical rebase

| Patch | Notes |
|-------|-------|
| **chromium/0001** `Add-Carbonyl-library.patch` | Only touches `headless/BUILD.gn`; target additions are stable. |
| **chromium/0005** `Remove-some-debug-assertions.patch` | Debug assertions in well-established files; some may have been removed upstream. |
| **chromium/0011** `Rename-carbonyl-Renderer-to-Bridge.patch` | Mechanical rename; context lines will have drifted. |
| **webrtc/0001** `Disable-GIO-on-Linux.patch` | GIO is also disabled at build level in `args.gn`; patch may be a no-op. |

---

## GN Args Audit

Before any build attempt, the following args in `src/browser/args.gn` must be verified against
the target Chromium version's GN arg list. Unknown args cause hard `gn gen` failures.

| Arg | Status | Action |
|-----|--------|--------|
| `enable_ppapi = false` | **Removed** — PPAPI deleted from Chromium | Remove immediately |
| `enable_nacl = false` | Likely removed | Verify; remove if gone |
| `enable_rust_json = false` | May be renamed/removed | Verify |
| `enable_screen_ai_service = false` | Screen AI expanded; arg may have changed | Verify |
| `enable_pdf = false` | PDF changed significantly | Verify arg still exists |
| `headless_enable_commands` | Still valid | No action |
| `headless_use_embedded_resources` | Still valid | No action |
| `ffmpeg_branding` | Still valid | No action |
| `ozone_platform = "headless"` | Still valid | No action |
| `use_static_angle = true` | Still valid; now works on all platforms | No action |

---

## Phased Upgrade Strategy

A direct jump from M111 to M135 through 24 milestones risks merge conflicts piling on top of each
other. A phased approach de-risks the rebase by stopping at points where the headless API
stabilized.

### Phase 0 — Pre-flight (no Chromium checkout needed)

1. Audit and fix `src/browser/args.gn` (remove `enable_ppapi`, verify others)
2. Read the current `text_painter_base.cc` in M135 to understand where to re-anchor Patch 07
3. Read the current `software_output_device_ozone.cc` to understand the new software output
   architecture for Patch 13 rewrite
4. Identify new base commits for Skia and WebRTC at target version

### Phase 1 — M111 → M120

**Goal:** Land the headless API stabilization point (post-`Options::Builder` removal)

Key changes to navigate:
- M112: New headless mode unifies code paths
- M115: Command line flag plumbing changes (`headless_browser.h`) — fix Patch 04
- ~M120: `ng_text_painter_base.cc` disappears — fix Patch 07 (critical path)
- ~M120: `Options::Builder` removed — fix Patch 04
- ~M120: `chrome-headless-shell` binary extracted (informational only; does not affect our build)

**Exit criteria:** All 17 patches apply cleanly on M120 and `ninja headless:headless_shell` succeeds.

### Phase 2 — M120 → M132

**Goal:** Navigate the headless Observer removal and window state changes

Key changes to navigate:
- ~M125: `HeadlessWebContents::Observer` removed — fix Patch 09
- ~M126: Window state string → enum — fix Patch 09
- ~M128: ChromeOS macro renames in ozone (audit patches for `IS_CHROMEOS_ASH`)
- ~M130: New `<module>-send-validation.h` mojom artifacts — update build expectations
- M132: `--headless=old` removed from Chrome binary (informational; does not affect our build)

**Exit criteria:** All patches apply cleanly on M132 and headless_shell builds.

### Phase 3 — M132 → M135

**Goal:** Land on stable target; navigate Viz Mojo interface removals

Key changes to navigate:
- ~M135: `OnBeginFrameAcks` removed from Viz
- ~M136: `CompositorFrameSinkType` removed, `SubmitCompositorFrameSync()` removed — fix Patch 03
- ~M136: Khronos/Mesa GL headers cleaned up — audit Patch 14 and Skia patches
- ~M137: `software_output_device_proxy.cc` gone — Patch 13 rewrite must be complete by this point
- ~M138: Skia Ganesh headers moved — fix Skia patches
- ~M140: `browser_interface_binders.cc` PopulateFrameBinders refactor — fix Patch 02
- ~M142: `viz::ResourceSizes` deleted; `shared_image_format` moved — fix Patch 03 build deps

**Exit criteria:** All patches apply cleanly on M135 and full Docker build produces a working binary.

---

## Patch 13 Rewrite (Separate Track)

Patch 13 (`Refactor-rendering-bridge.patch`) is the largest and most complex patch (1008 lines)
and requires a rewrite, not a rebase. It should be treated as a parallel workstream.

**What the patch does today (M111):**
- Creates `software_output_device_proxy.cc` — a new file that intercepts the Chromium software
  output device to capture pixel data via shared memory
- Registers this proxy as the display output in the display embedder
- Connects the Viz software output path to Carbonyl's Rust rendering pipeline

**What must be done for M135:**
1. Understand the current `software_output_device_ozone.cc` interface (Linux headless path)
2. Design the new hook point — either subclassing `SoftwareOutputDeviceOzone` or intercepting
   at `OutputSurfaceProviderImpl`
3. Implement equivalent shared-memory pixel capture
4. Ensure the IPC path back to the Rust bridge (`libcarbonyl.so`) still works

This is the single highest-risk item in the upgrade. Allocate dedicated time before starting Phase 3.

---

## Build Verification Checkpoints

At each phase exit, run the following before advancing:

```bash
# 1. Verify GN configuration succeeds
./scripts/gn.sh gen out/Default --args="..."

# 2. Verify build compiles
ninja -C out/Default headless:headless_shell

# 3. Verify Rust library links
cargo build --release

# 4. Smoke test (headless render)
./out/Default/headless_shell --headless --disable-gpu \
  --screenshot=test.png https://example.com
```

---

## Runtime Infrastructure

After a successful build, the pre-built runtime at `carbonyl.fathy.fr` will be stale. The CDN
upload step is currently documented but the CDN credentials (`CDN_ACCESS_KEY_ID`,
`CDN_SECRET_ACCESS_KEY`) are not yet configured for this fork. This is a separate concern from
the build work but must be resolved before `build-local.sh` can be used by others.

Options:
1. Configure CDN credentials in repository secrets and update `scripts/runtime-push.sh` for the
   new host
2. Switch `build-local.sh` to use a self-hosted artifact store (e.g., Gitea releases)

---

## Reference Links

- Chromium releases dashboard: https://chromiumdash.appspot.com/releases
- Chrome for Testing: https://googlechromelabs.github.io/chrome-for-testing/
- Chromium headless docs: https://chromium.googlesource.com/chromium/src/+/main/headless/README.md
- Skia change log: https://skia.googlesource.com/skia/+log/
- Mojo documentation: https://chromium.googlesource.com/chromium/src/+/main/mojo/README.md
- Viz documentation: https://chromium.googlesource.com/chromium/src/+/main/components/viz/README.md
- depot_tools: https://commondatastorage.googleapis.com/chrome-infra-docs/flat/depot_tools/docs/html/depot_tools_tutorial.html
