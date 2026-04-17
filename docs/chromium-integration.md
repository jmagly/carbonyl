# Chromium Integration Catalog

**Status**: Living document. This catalog is the single source of truth for every Carbonyl-specific modification to the upstream Chromium tree.

**Scope**: Everything that makes the Chromium build behave like Carbonyl — not just patches. Covers:

- Chromium patches (`chromium/patches/chromium/*.patch`)
- Skia and WebRTC patches (`chromium/patches/{skia,webrtc}/*.patch`)
- Injected C++ sources under `chromium/src/carbonyl/` (net-new files the patches reference)
- FFI contract between Rust (`libcarbonyl.so`) and Chromium (`carbonyl::Bridge`, `carbonyl::Renderer`)
- Build-system additions (`args.gn`, Carbonyl-specific `BUILD.gn`)

**Why it exists**: Issue #37 surfaced a DSF-plumbing bug that spans three patches, two injected source files, and one FFI contract — reconstructing "why is this like this" required reading five separate files with no map between them. The m120→m135→m147 upgrade path (captured in `MAINTENANCE.md`) is also evidence of how expensive patch drift is without written-down invariants. This catalog is the map.

**Not in scope**: How to sync / build / rebase. That's in `MAINTENANCE.md` and `docs/chromium-upgrade-plan.md`.

---

## Table of contents

- [Conventions](#conventions)
  - [Patch entry template](#patch-entry-template)
  - [Injected-source entry template](#injected-source-entry-template)
  - [FFI entry template](#ffi-entry-template)
  - [Build-system entry template](#build-system-entry-template)
  - [Patch file header comment convention](#patch-file-header-comment-convention)
- [Chromium patches](#chromium-patches)
  - [Library setup (0001–0005)](#library-setup-00010005) — *tracked in #39*
  - [Display DPI and text (0006–0008)](#display-dpi-and-text-00060008) — *tracked in #40*
  - [Bridge and rendering refactor (0009–0014)](#bridge-and-rendering-refactor-00090014) — *tracked in #41*
  - [Version-compat fixes (0015–0024)](#version-compat-fixes-00150024) — *tracked in #42*
- [Skia and WebRTC patches](#skia-and-webrtc-patches) — *tracked in #43*
- [Injected C++ sources](#injected-c-sources) — *tracked in #45*
- [FFI contract](#ffi-contract) — *tracked in #44*
- [Build-system additions](#build-system-additions)
- [Design notes](#design-notes)
  - [Patch 0025 (planned): Viz output device DSF](#patch-0025-planned-viz-output-device-dsf) — *tracked in #47, #48*

---

## Conventions

### Patch entry template

Each patch under `chromium/patches/chromium/` gets one subsection. Use this exact structure so grep and anchor links stay predictable.

```markdown
### Patch 00NN — Short title

**Group**: Library setup | Display/DPI | Bridge/rendering | Text | Version-fix

**Upstream files touched**:
- `relative/path/from/chromium/src/file.cc` — one-line note on what changed
- `relative/path/from/chromium/src/file.h` — one-line note on what changed

**What it changes**: One paragraph describing concrete behavior, not a restatement of the diff. Answer: "if I revert this patch, what visibly breaks?"

**Why Carbonyl needs it**: One paragraph on the problem being solved and what the patch enables for Carbonyl.

**Depends on**: Other patches this patch requires to apply or function. Brief why.

**Depended on by**: Patches or injected source that would break if this patch were removed.

**Rebase hotspots**: Upstream files whose signatures/structure have changed across past m-versions and are likely to change again.

**Related issues/PRs**: #N links.

**Status**: Upstream-submitted | Not submitted | Carbonyl-specific (won't be upstreamed)
```

### Injected-source entry template

Each file under `src/browser/*.{h,cc,rs,mojom}` or net-new source that lives inside the Chromium tree at build time gets one subsection.

```markdown
### `path/to/file.cc` (injected)

**Purpose**: One line.

**Public API**:
- `Symbol` — what it does, who calls it.

**State owned**: Singletons, statics, ownership chains.

**Threading**: Which thread(s) call it. Contention model. Send/Sync status for Rust.

**Depended on by patches**: 00NN, 00MM — how.

**FFI surface**: Which FFI functions declared or consumed here (cross-link to the FFI section).

**Fragile spots**: Known quirks, footguns, rebase-era bugs.
```

### FFI entry template

Every function crossing the Rust ↔ Chromium boundary. Both directions.

```markdown
### `function_name` (Chromium → Rust | Rust → Chromium)

**C signature**: `...`

**Rust signature**: `...`

**Threading**: Calling thread, return thread, blocking behavior.

**Lifetime**: Pointer ownership, Send/Sync, drop semantics.

**Invariant**: The contract that must not break. Be specific — vague invariants kill at rebase time.

**Callers**: Where this function is invoked (file:line if in-tree, module path if upstream).

**Depended on by patches**: 00NN — how.

**Fragile spots**: Known cross-platform quirks, ABI traps.
```

### Build-system entry template

```markdown
### `path/to/args.gn` or `BUILD.gn`

**Purpose**: What this file configures.

**Key flags**: Grouped by concern. For each: what the flag does, why Carbonyl sets it, what breaks if it's removed.

**Interactions with patches**: Which patches depend on which flags.

**Rebase hotspots**: GN flag renames and removals observed across m-versions.
```

### Patch file header comment convention

Every `.patch` file gets a one-line comment at the very top pointing back at its catalog entry, so a reader opening the patch can find context without a grep:

```text
# Catalog: docs/chromium-integration.md#patch-0006--setup-display-dpi
From 2d8632abfa2fd7c0a2c9ed44136bb8c634afac3a Mon Sep 17 00:00:00 2001
From: Fathy Boundjadj <hey@fathy.fr>
...
```

The anchor format is GitHub-flavored: lowercase, spaces → hyphens, em-dashes → double-hyphens, other punctuation stripped. Test with a real render before committing.

---

## Chromium patches

### Library setup (0001–0005)

*Audit tracked in #39.* Placeholder — not yet audited.

### Display DPI and text (0006–0008)

*Audit issue #40. Audited 2026-04-16 against `chromium/src @ 147.0.7727.85-639`.*

### Patch 0006 — Setup display DPI

**Group**: Display/DPI

**Upstream files touched**:
- `headless/lib/browser/headless_platform_delegate_aura.cc` — routes `SetWebContentsBounds` through `ScaleToEnclosedRect(bounds, dpi)` so window-tree-host pixel bounds match the DSF-scaled physical size
- `headless/lib/browser/headless_screen.cc` — when building the display list, calls `display.SetScaleAndBounds(dpi, ScaleToEnclosedRect(it.bounds, dpi))` so the headless display knows its DSF
- `ui/display/display.cc` — unconditionally enables `HasForceDeviceScaleFactor` and wires `GetForcedDeviceScaleFactorImpl` to `carbonyl::Bridge::GetCurrent()->GetDPI()`

**What it changes**: Makes `display::Display::GetForcedDeviceScaleFactor` globally return the Carbonyl-computed DPI (`Window::dpi`) rather than a CLI-switch-controlled value, and threads that DPI through headless window-tree-host bounds and the display metadata. After this patch, Blink sees the correct CSS-vs-device pixel ratio and media queries like `devicePixelRatio` match what Carbonyl computed from terminal cell size. Additionally, `SetScale`/`SetScaleAndBounds` no longer round DSF to integral values on Apple, and the `std::max(0.5f, …)` floor is removed (sub-unit DSFs are valid here).

**Why Carbonyl needs it**: A terminal cell doesn't correspond to 1 CSS pixel. Carbonyl samples a 2×4 source-pixel quadrant per cell (see [FFI: `carbonyl_renderer_get_size`](#carbonyl_renderer_get_size-chromium--rust)). For web content to lay out correctly against that physical-pixel budget, Chromium needs a fractional DSF (≈ 0.38 at default 220×50 terminals). Without this patch the page lays out at DSF=1, producing either a tiny-looking layout in the available cells or an upper-left crop depending on other patches.

**Depends on**: 0001 (introduces `carbonyl::Bridge`, whose `GetDPI` this patch calls)

**Depended on by**: 0013 (routes the same DPI into `HeadlessScreen::Resize` and `SetScaleAndBounds`); the Viz output device fix tracked in #47 / #48 (completes the DSF chain into the buffer the Rust renderer samples — planned edit to `chromium/src/carbonyl/src/viz/carbonyl_software_output_device.cc`, see [Design notes](#patch-0025-planned-viz-output-device-dsf--likely-not-a-chromium-patch))

**Rebase hotspots**:
- `ui/display/display.cc` — the `HasForceDeviceScaleFactorImpl` / `GetForcedDeviceScaleFactorImpl` signatures and the `g_has_forced_device_scale_factor` flag have moved around across m-versions; verify at every rebase that the override still reaches Blink
- `headless/lib/browser/headless_screen.cc` — `SetDisplayGeometry` signature changed between m120 and m135
- Apple-specific guard (`#if BUILDFLAG(IS_APPLE)`) around integral DSF; keep removed or the integral cast re-introduces the bug on macOS

**Related issues/PRs**: #37 (the mechanism; this patch reaches display metrics but NOT the Viz output device buffer, which is the root of the bug), #40 (audit), #47 (Viz investigation), #48 (completion via `carbonyl_software_output_device.cc` edit)

**Status**: Carbonyl-specific — unlikely to be upstreamed (it forces a policy change that conflicts with the optional-override design of `kForceDeviceScaleFactor`).

### Patch 0007 — Disable text effects

**Group**: Text

**Upstream files touched**:
- `third_party/blink/renderer/core/paint/text_decoration_painter.cc` — comments out the underline and overline `PaintDecorationLine` calls inside `PaintUnderOrOverLineDecorations`
- `ui/gfx/render_text.cc` — comments out the bodies of `SkiaTextRenderer::DrawUnderline` and `SkiaTextRenderer::DrawStrike` (strikethrough), and the two `kStrikeThroughOffset` / `kUnderlineOffset` constants that fed them

**What it changes**: Blink still tracks `text-decoration: underline/overline/line-through` in the computed style but emits zero Skia draw calls for them. CSS underlines, overlines, strikethroughs, and ui/gfx's own text-rendering underline/strike calls are no-ops.

**Why Carbonyl needs it**: Chromium's decoration drawing aliases horribly against the 2×4 sub-pixel quadrant sampled by the terminal renderer — a one-pixel underline would only hit the bottom half of a row occasionally, producing a flickering dashed appearance rather than a clean line. Carbonyl's text rendering path runs separately (see patches 0010, 0014) and draws its own cell-aligned underline when needed. Disabling Chromium's version removes the visual noise.

**Depends on**: None structurally; the patch only removes/comments code.

**Depended on by**: None directly. The terminal-side text-rendering path in `src/output/` assumes underlines/strikes aren't in the background buffer, so removing this patch would produce double-drawn decorations.

**Rebase hotspots**:
- `text_decoration_painter.cc::PaintUnderOrOverLineDecorations` is restructured roughly every other m-version (DecorationGeometry was introduced mid-series, not pre-m120; BaselineForInkSkip is a recent addition). The commented-out block in this patch reflects the pre-m120 shape; post-m135 the equivalent calls now take a `DecorationGeometry` built from `ComputeUnderlineLineData`. Verify the replacement commented-out block still covers the live paint path at each rebase.
- `ui/gfx/render_text.cc::SkiaTextRenderer` interface is stable but the `kUnderlineOffset` / `kStrikeThroughOffset` names and formulas have drifted.
- 0020 (`fix-m120-fix-Blink-font-API-changes-in-style_resolve`) is a sibling fix, possibly re-patching something that 0007 or 0008 had to re-apply after an API break.

**Related issues/PRs**: #40 (audit).

**Status**: Carbonyl-specific — not upstreamable (it's a deliberate capability removal).

### Patch 0008 — Fix text layout

**Group**: Text

**Upstream files touched**:
- `third_party/blink/renderer/core/css/resolver/style_resolver.cc` — two changes:
  1. `ComputeBaseComputedStyleDiff` short-circuits to `g_null_atom` instead of returning a "Field diff: …" breadcrumb (with a TODO-fathy comment)
  2. Inside `StyleResolver::ResolveStyle`, the `HasSiblingFunctions()` branch that propagates `SetChildrenAffectedBy{Forward,Backward}PositionalRules` to the parent tree-counting element is **replaced** by an unconditional font override that forces every element to a fixed monospace font description

**What it changes**: Every resolved element's computed style gets overwritten with:
- `font-family: monospace` (generic family)
- `font-stretch: extra-expanded`
- `font-kerning: none`
- `computed-size: 11.75 / 7.0` CSS units (≈ 1.679)
- `line-height: 14.0 / 7.0` (exactly 2.0) fixed
- `generic-family: monospace`
- `is-absolute-size: true`

After this patch, the resolved style is effectively uniform across the document: everything is monospace, everything is the same size, everything has the same line-height. CSS-specified fonts/sizes/weights are discarded at the resolver stage.

**Why Carbonyl needs it**: Terminal cells are a fixed-pitch grid. Proportional fonts can't tile into that grid without cell-boundary artifacts. The 11.75/7.0 and 14.0/7.0 magic numbers are empirical: they place glyph centers inside the 2×4 quadrant sampled per cell. Without this patch, web content renders at whatever size the page requested, which at Carbonyl's fractional DSF usually means text falls between sampling quadrants and becomes unreadable.

**Depends on**: None structurally. The replaced `HasSiblingFunctions` block was added post-m120 (sibling-pseudo-class tree counting is an M133-era feature), which suggests this patch is a re-application of an older font override that landed somewhere else in earlier m-versions.

**Depended on by**: The font-metrics assumptions in `src/output/renderer.rs` and in patches 0010 / 0014 assume monospace text from Blink.

**Rebase hotspots** (this patch is the most fragile in the stack):
- The location of the font override inside `ResolveStyle` has moved every major rebase. In m111 it lived earlier in the function; in m135 it sits where the sibling-functions branch used to be; by m147 it will likely need another new home.
- The magic numbers `11.75 / 7.0` and `14.0 / 7.0` have no explanatory comment in upstream. **Document them** if you touch this patch. Guess: 7.0 is `cell_pixels.width - 1` (historical cell inner width); 11.75 is a tuned font-size that keeps glyph bounding boxes inside a 2×4 quadrant. Needs verification.
- `ComputeBaseComputedStyleDiff` is DCHECK-only; removing the breadcrumb only affects debug builds. Safe at rebase time.
- `FontDescription::SetKerning` has been renamed at least once (was `SetTypesettingFeatures` in older m-versions).

**Related issues/PRs**: #40 (audit). Also related to patches 0010, 0014 (the text-rendering toggles this patch's output feeds into).

**Status**: Carbonyl-specific — not upstreamable.

### Bridge and rendering refactor (0009–0014)

*Audit tracked in #41.* Placeholder — not yet audited.

### Version-compat fixes (0015–0024)

*Audit tracked in #42.* Placeholder — not yet audited. See [MAINTENANCE.md](../MAINTENANCE.md#chromium-version) for the rebase history (M111 → M120 → M132 → M135 → M140 → M147) that produced these fixes; several may now be fold-in candidates.

---

## Skia and WebRTC patches

*Audit tracked in #43.* As of this writing both `chromium/patches/skia/` and `chromium/patches/webrtc/` are empty. The earlier `docs/chromium-upgrade-plan.md` references 2 Skia and 1 WebRTC patch that existed at M111; those appear to have been folded into the Chromium patch set or resolved upstream during the M120→M135 rebase. The audit should confirm and document.

---

## Injected C++ sources

*Audit tracked in #45.* Placeholder.

#### Example entry (illustrative, to be validated when #45 lands)

### `src/browser/bridge.cc` (injected)

**Purpose**: Static accessor for the DPI and bitmap-mode settings that Chromium patches need to consult during display / rendering setup.

**Public API**:
- `carbonyl::Bridge::GetDPI()` → `float` — called by `ui/display/display.cc` (patch 0006), `headless_screen.cc` (patch 0013)
- `carbonyl::Bridge::BitmapMode()` → `bool` — called by the text-rendering code paths (patches 0010, 0014)
- `carbonyl::Bridge::Configure(float dpi, bool bitmap_mode)` — called once at startup by `Renderer::Main()`
- `carbonyl::Bridge::Resize()` — currently a no-op; intended entry point for dynamic DSF changes on terminal resize

**State owned**: Two file-scope statics (`dpi_`, `bitmap_mode_`) behind the `carbonyl` namespace. Set once during startup by `Configure`; read many times thereafter. No synchronization — assumes startup ordering.

**Threading**: `Configure` runs on the browser main thread at process startup, before Chromium reads the values. `GetDPI` / `BitmapMode` are called from whatever thread reaches the caller (UI thread for display metadata, compositor for text mode). **Footgun**: there is no memory barrier; if DSF ever needs to change at runtime (per `Resize`), the current code races.

**Depended on by patches**: 0006 (uses `GetDPI` in `display.cc`), 0010 (uses `BitmapMode` in text paths), 0013 (uses `GetDPI` in `headless_screen.cc` Resize path), 0014 (uses `BitmapMode` in Skia text control)

**FFI surface**: Consumes [`carbonyl_bridge_get_dpi`](#carbonyl_bridge_get_dpi-chromium--rust) via `Renderer::Main()` → `Bridge::Configure`.

**Fragile spots**:
- Statics are initialized to 0.0 / false. If any code path reads DPI before `Configure` runs, it gets 0.0 — divide-by-zero in downstream math.
- `Bridge::Resize()` is declared but empty; dynamic terminal resize currently relies on the Rust side re-running `Window::update()` and Chromium re-invoking `carbonyl_renderer_get_size`. Document this contract before anyone wires up Bridge::Resize.

---

## FFI contract

*Audit tracked in #44.* Placeholder.

#### Example entry (illustrative, to be validated when #44 lands)

### `carbonyl_renderer_get_size` (Chromium → Rust)

**C signature**: `struct carbonyl_renderer_size carbonyl_renderer_get_size(struct carbonyl_renderer* renderer);`

**Rust signature**: `pub extern "C" fn carbonyl_renderer_get_size(bridge: RendererPtr) -> CSize;`

**Threading**: Called from the browser main thread during display list / window sizing. Returns synchronously. Internally takes `Mutex<RendererBridge>` — must not be called from a context that already holds that mutex.

**Lifetime**: Return value is by-value (POD struct). `renderer` is a Rust-owned `Arc<Mutex<RendererBridge>>` allocated in `carbonyl_renderer_create` and held by Chromium for the process lifetime.

**Invariant**: The returned size is the **CSS viewport** Chromium should lay out against — `cells × scale` where `scale = (2, 4) / dpi`. The physical raster the Rust renderer actually samples is `cells × (2, 4)`, which Chromium derives by multiplying this CSS viewport by the DSF returned from [`carbonyl_bridge_get_dpi`](#carbonyl_bridge_get_dpi-chromium--rust). That multiplication happens in `components/viz/service/display_embedder/software_output_device_proxy.cc::SoftwareOutputDeviceBase::Resize` (see [Design notes](#viz-output-device-dsf-fix--applied-2026-04-16-extends-patch-0013)). If that multiplication is dropped, the physical raster stays CSS-sized while Rust samples physical-sized — the upper-left `dpi²` fraction of the page is all that reaches the terminal (issue #37).

**Callers**: `chromium/src/carbonyl/src/browser/renderer.cc::Renderer::GetSize` (consumed by patch 0013's `HeadlessScreen::Resize` and `context_builder.SetWindowSize`, which feed Chromium's compositor)

**Depended on by patches**: 0013 (primary consumer via `context_builder.SetWindowSize(carbonyl::Renderer::GetCurrent()->GetSize())`). Must be used together with `carbonyl_bridge_get_dpi` — the CSS-viewport-plus-DSF pair is what makes the overall DSF chain consistent.

**Fragile spots**:
- `CSize` field order must match the C `struct carbonyl_renderer_size` declaration byte-for-byte. Keep both in sync at every ABI change.
- The mutex inside `bridge` is uncontended at startup; if Chromium ever calls `get_size` concurrently with `draw_bitmap` (which also locks the mutex), we'd deadlock. This hasn't happened in practice but isn't guaranteed.

### `carbonyl_bridge_get_dpi` (Chromium → Rust)

**C signature**: `float carbonyl_bridge_get_dpi();`

**Rust signature**: `pub extern "C" fn carbonyl_bridge_get_dpi() -> c_float;`

**Threading**: Called from the browser main thread during early Chromium startup (from `carbonyl::Renderer::Main()` → `carbonyl::Bridge::Configure`). Also potentially re-read later by `carbonyl::Bridge::GetDPI()` across the process lifetime. Synchronous.

**Lifetime**: POD return. No pointer semantics. The Rust side constructs a fresh `Window::read()` on every call, which includes an `ioctl(TIOCGWINSZ)` and `CommandLine::parse()` — not free, but low-frequency (roughly once per terminal resize + once at startup).

**Invariant**: The returned value is the **device scale factor** — the ratio of physical pixels to CSS pixels. For Carbonyl it equals `2 / cell_width * zoom`, which resolves to ~0.38 at the default 220×50 terminal. This value propagates through two independent chains:
1. `display::Display::GetForcedDeviceScaleFactor` (see patch 0006) — affects Blink's `devicePixelRatio`, media queries, and layout
2. `viz::SoftwareOutputDeviceBase::Resize` post-fix (see Design notes) — scales the CSS viewport to allocate the physical raster buffer

Both chains MUST return the same value. If they drift (e.g. a future patch introduces a cached copy that gets stale), the raster size won't match what Blink expects and rendering breaks.

**Callers**:
- `chromium/src/carbonyl/src/browser/renderer.cc::Renderer::Main` — once at process startup, feeds the value into `carbonyl::Bridge::Configure`
- Indirectly via `carbonyl::Bridge::GetDPI()` from `ui/display/display.cc` (patch 0006), `headless/lib/browser/headless_screen.cc` and `headless_platform_delegate_aura.cc` (patches 0006, 0013), and `software_output_device_proxy.cc` via the `scale_factor` argument plumbed by upstream

**Depended on by patches**: 0006 (the primary DSF routing), 0013 (re-reads for `HeadlessScreen::Resize`), and the 2026-04-16 Viz fix (consumes the DSF as the `scale_factor` argument to `SoftwareOutputDeviceBase::Resize`)

**Fragile spots**:
- Returning 0.0 or a value < 0.5 breaks downstream math in Blink (divide-by-zero or unrealistically large CSS viewports). The Rust side guards against terminal sizes of zero via `term.width.max(1)` / `term.height.max(2) - 1`; don't weaken those.
- The C signature returns `float`; Rust uses `c_float`. On all our supported platforms these are identical IEEE-754 32-bit floats, but ABI-wise this couple is worth keeping in mind at any LLVM / compiler flag change.
- `Window::read()` performs CLI arg parsing every call. Changing this to a cached value is a latent bug waiting to happen unless the cache invalidation on `SIGWINCH` is wired up.

---

## Build-system additions

### `src/browser/args.gn`

**Purpose**: Chromium build flags required for a Carbonyl build to compile and link. Written once, consumed by `gn gen` during every build.

**Key flags**:

*Headless-shell configuration*:
- `headless_enable_commands = false` — Carbonyl uses its own FFI-driven command loop, not Chromium's
- `headless_use_embedded_resources = true` — no external .pak files at runtime

*Component vs static build*:
- `is_component_build = false` — **required**. Carbonyl's `TextCaptureDevice` inherits from internal Skia classes (`SkDevice`, `SkClipStackDevice`) whose symbols are not exported from the Skia shared library in a component build. Forcing static build makes these symbols visible. Removing this flag breaks the Skia-side text capture introduced by patch 0014.

*Media*:
- `ffmpeg_branding = "Chrome"` + `proprietary_codecs = true` — enable H.264 etc. so mainstream sites play video

*Ozone / display*:
- `ozone_platform = "headless"` with `ozone_platform_x11 = false` — Carbonyl has no window server, so no X11
- `use_qt/gio/gtk/cups/xkbcommon = false` — prune desktop-env deps
- `use_dbus = true` — **required as of M147**. Wayland ozone unconditionally depends on `clipboard_util_linux` which requires dbus; setting `use_dbus = false` breaks the build even though Carbonyl doesn't use dbus. Document whenever this constraint relaxes upstream.

*Feature flags*:
- `enable_nacl = false`, `enable_media_remoting = false`, `enable_system_notifications = false` — unused, safe to disable
- **Do not** blanket-disable other feature flags in M135+. Setting them to `false` triggers GN `assert()` failures in test `BUILD.gn` files that the `gn_all` root group transitively loads during `gn gen`. See the in-file comment for details; this is a real bite from past rebases.

**Interactions with patches**:
- `is_component_build = false` is load-bearing for patches 0014 (Skia text control) and 0010 (text rendering enable/disable)
- `ozone_platform = "headless"` is assumed by 0003 (shared software rendering surface)
- `headless_enable_commands = false` aligns with 0002 (Carbonyl service) replacing the built-in commands path

**Rebase hotspots**:
- GN flag renames: `use_dbus` was forceable before M147; watch for similar reversals
- Skia's component-build export list has changed multiple times (see 0014's rebase fixes in patches 0019, 0021)
- Ozone platform names and default sets drift across milestones

---

## Design notes

### Viz output device DSF fix — *attempted and reverted; not the actual fix for #37*

*Tracked in #47 (investigation) and #48 (implementation). Applied 2026-04-16, reverted 2026-04-17 after a runtime A/B produced byte-identical output pre/post-fix. Documented here so future readers don't redo the investigation.*

**Actual resolution**: `--viewport=WIDTHxHEIGHT` CLI flag (and `CARBONYL_VIEWPORT` env var) landed on the Rust side. The SDK provides the CSS viewport it wants Blink to lay out against; DSF is forced to 1.0; Chromium rasters at that exact size; the terminal samples a `cells × (2, 4)` window of it. Verified 2026-04-17 — full X login modal visible at `--viewport=1280x800` on 500×150 terminal. See [rust-chromium-boundary.md § SDK-driven viewport](rust-chromium-boundary.md#sdk-driven-viewport) for the pattern.

**Problem**: The DSF chain wired by patch 0006 reaches `display::Display` metrics but not the backing buffer the Carbonyl Rust renderer samples from. At a 220×50 terminal with `dpi = 0.38`, Chromium's compositor allocates a `(1157, 516)` pixel buffer, while the Rust renderer only samples the upper-left `(440, 196)` region — the visible output is the upper-left ~14% of the page (see #37).

**Where the DSF is dropped**: `components/viz/service/display_embedder/software_output_device_proxy.cc::SoftwareOutputDeviceBase::Resize` accepts `(viewport_pixel_size, scale_factor)` and stores only `viewport_pixel_size_`, ignoring `scale_factor`. This file is already patched by **patch 0013** (bridge refactor); the DSF fix extends the patch-0013 modifications to that file.

**Note on the Carbonyl-owned `chromium/src/carbonyl/src/viz/carbonyl_software_output_device.{h,cc}`**: those files exist in the tree but are **dead code**. No build target depends on `//carbonyl/src/viz:viz`, and no source in `components/viz/` or `content/` references `CarbonylSoftwareOutputDevice`. The file header claims it's the active implementation following a post-M132 extraction, but that migration was prepared and not carried through. Left as-is for future rebases but flagged here so subsequent readers don't trust the header comment over `grep`.

**Upstream caller chain** (verified on this tree, `chromium/src` at `147.0.7727.85-639`):
1. `components/viz/service/display/direct_renderer.cc:351-352` populates `reshape_params.size` (upstream calls this "physical pixels") and `reshape_params.device_scale_factor`.
2. `components/viz/service/display/direct_renderer.cc:364` calls `Reshape(reshape_params)`.
3. `components/viz/service/display_embedder/software_output_surface.cc:55` calls `software_device()->Resize(params.size, params.device_scale_factor)`.
4. `chromium/src/carbonyl/src/viz/carbonyl_software_output_device.cc:33-43` **ignores** `scale_factor`.

**Why the upstream "physical" size is actually CSS**: Carbonyl feeds Chromium its CSS viewport via `context_builder.SetWindowSize(carbonyl::Renderer::GetCurrent()->GetSize())` — `GetSize()` returns `Window::browser = cells × scale` (CSS bounds, computed in Rust). That flows through `device_viewport_size` → `surface_resource_size` → `params.size` without ever being multiplied by DSF, so what upstream calls "physical" is, in Carbonyl's setup, still CSS.

**Why it didn't work** (diagnostic result from carbonyl-agent team A/B test, 2026-04-17):

The edit made `viewport_pixel_size_` physical (`cells × (2, 4) = 1000×596` at 500×150 terminal) instead of CSS (`2632×1569`). Ninja rebuilt `proxy.o`, relinked `headless_shell`, and Rust-side `log::warning!` confirmed `pixels_size=1000x596` at the FFI boundary post-fix — exactly what the hypothesis predicted. But the rendered PNG was **byte-identical** to the pre-fix run.

The reason: Blink's upstream layout path was never touched by this fix. `carbonyl_renderer_get_size` still returned `cells × scale = 2632×1569` CSS, which Chromium's plumbing combined with DSF=0.38 to infer a ~6926×4129 CSS viewport. Blink laid out the page against that, rasterised to physical pixels, and wrote the same content into the sampled region regardless of whether the output buffer was 1000×596 (post-fix) or 2632×1569 pre-fix (where only the upper-left 1000×596 was sampled). Either way the X login modal at logical-CSS center-x≈3463 landed at physical x≈1316 — outside the 0..1000 sampled range.

**The actual fix**: change what Blink lays out against. That's an SDK-level concern (different sites want different viewports), so it became a Rust CLI/env affordance, not a Chromium patch. See above.

**Lesson logged**: a C++ edit to shrink the raster buffer to match the sampled region does not shrink the CSS layout upstream. If the sampled region is a strict subset of the rasterised content *in CSS space*, only a CSS-viewport change reaches the user-visible layout.
