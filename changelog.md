# Changelog

All notable changes to this project will be documented in this file.

---

## [Unreleased] — jmagly/carbonyl fork

This section covers work done in the `jmagly/carbonyl` fork since the upstream
(`fathyb/carbonyl`) became inactive in February 2023. The fork maintains
Carbonyl for use in automated agent testing pipelines and upgrades the
Chromium base through M147.

### Chromium Upgrade: M140 → M147 — SHIPPED (Apr 2026)

Phase 2 of the M135 → M147 catch-up epic. All 24 patches rebased from
M140 to M147 (147.0.7727.94) — current upstream stable.

| Phase | Milestone | Commit |
|-------|-----------|--------|
| Phase 2 | M147 (147.0.7727.94) | `58e50bd` |

**Patch count**: 24 (unchanged).

**Runtime tarball**: published to Gitea releases as
[`runtime-c6fd85745eeaaf1b`](https://git.integrolabs.net/roctinam/carbonyl/releases/tag/runtime-c6fd85745eeaaf1b)
(x86_64-unknown-linux-gnu).

#### Patch conflicts resolved (11)

- **Patch 01** (`headless/BUILD.gn`): merged M147 deps with carbonyl dep
- **Patch 02**: kept carbonyl Mojo members alongside M147's `BrokerHolder`
  struct refactor in `render_frame_host_impl.h`; dropped
  `CONTENT_ENABLE_LEGACY_IPC` blocks (removed in M147)
- **Patch 03** (`host_display_client.h`): kept `LayeredWindowUpdater`
  Mojo interface alongside M147's M147 IS_MAC refactor
- **Patch 05** (`paint_artifact_compositor.cc`): removed debug dump calls
  (carbonyl side)
- **Patch 06** (`headless_screen.cc`): kept carbonyl bridge include and
  DPI scaling
- **Patch 07** (`text_decoration_painter.cc`): kept disabled underline/overline
- **Patch 09**: merged headless_web_contents / browser_impl includes
- **Patch 10** (`render_frame_impl.cc`): merged M147 perfetto includes
  with carbonyl Skia include
- **Patch 13** (6 files): merged includes and deps across the rendering
  bridge refactor
- **Patch 23**: merged `headless_browser_impl.cc` includes
- **Patch 24** (`blink/renderer/platform/BUILD.gn`): added carbonyl
  text_capture visibility

#### Build fixes for M147 API drift

- **GN args**: `use_dbus = true` required — M147's wayland ozone now
  unconditionally depends on `clipboard_util_linux` which needs dbus
- **`renderer.cc`**: replaced `static std::unique_ptr<Renderer>` with a
  leaked raw pointer — M147 clang enforces `-Wexit-time-destructors`
- **`text_capture.cc`** (Skia API drift):
  - `drawPath(path, paint, bool=false)` → `drawPath(path, paint)` (2-arg)
  - `getRelativeTransform` returns `SkM44`, use `.asM33()` for `SkMatrix`
  - Static `RendererService` → leaked pointer
- **`host_display_client.h`**: `ui/gfx/native_widget_types.h` renamed to
  `ui/gfx/native_ui_types.h`; added `SkBitmap.h` include; viz target
  now depends on `//ui/gfx`
- **`host_display_client.cc`**: removed obsolete `resource_sizes.h` include
- **`software_output_device_proxy.cc`**: `ResourceSizes::MaybeSizeInBytes`
  removed; replaced with `SinglePlaneFormat::kRGBA_8888.MaybeEstimatedSizeInBytes()`
- **`browser_interface_binders.cc`**: `BinderMap::Add` signature changed;
  switched carbonyl from manual `BindRepeating` to `BindRenderFrameHostImpl<>`
- **`headless_browser_impl.cc`**: added `navigation_controller.h` include;
  `PlatformSetWebContentsBounds` → `SetWebContentsBounds` (renamed)
- **`headless_screen.cc`**: removed duplicate `~HeadlessScreen() = default`
- **`headless_web_contents_impl.h`**: added
  `using content::WebContentsObserver::OnVisibilityChanged;`
- **`text_decoration_painter.cc`**: `(void)skip_ink` to suppress unused-var
- **`paint_artifact_compositor.cc`**: removed orphan
  `DumpWithDifferingPaintPropertiesIncluded` definition
- **`font.{h,cc}`**: removed dead `Font::DrawText(TextRun)` overloads —
  `CachingWordShaper` and `ShapeResultBuffer` removed upstream; the
  `TextFragmentPaintInfo` path with the b64 text-capture bypass remains

**Phantom dep fix**: removed `//carbonyl/src/browser:carbonyl` from
`headless/BUILD.gn` — target never existed (only `bridge`, `viz`,
`renderer`). Previously worked by accident in older gn evaluations.

### Chromium Upgrade: M135 → M140 — SHIPPED (Apr 2026)

Phase 1 of the M135 → M147 catch-up epic. Single-hop rebase of all 24
patches from M135 to M140 (140.0.7339.264).

| Phase | Milestone | Commit |
|-------|-----------|--------|
| Phase 1 | M140 (140.0.7339.264) | `5f165fe` |

**Patch count**: 24 (unchanged from M135).

**Runtime tarball**: published to Gitea releases as
[`runtime-35de92813b596ca2`](https://git.integrolabs.net/roctinam/carbonyl/releases/tag/runtime-35de92813b596ca2)
(238 MB, x86_64-unknown-linux-gnu).

#### Patch conflicts resolved (7)

- **Patch 02** (`render_frame_impl.cc`): M140 removed `CONTENT_ENABLE_LEGACY_IPC`
  blocks — dropped legacy IPC guards, kept carbonyl callback cleanup
- **Patch 02** (`font.cc`): Carbonyl b64 text additions — clean take of carbonyl
  side (M140 had no changes to this region)
- **Patch 06** (`headless_browser_impl_aura.cc`): M140 simplified `SetBoundsInPixels`
  — kept carbonyl DPI scaling via `ScaleToEnclosedRect`
- **Patch 07** (`text_decoration_painter.cc`): M140 added `TextDecorationSkipInk`
  checks — kept carbonyl's disabled underline/overline
- **Patch 08** (`style_resolver.cc`): M140 refactored sibling function tracking
  — kept carbonyl monospace font forcing
- **Patch 09** (`headless_web_contents_impl.h`): M140 added `HeadlessWindowDelegate`
  base class — kept both it and carbonyl's `WebContentsObserver`
- **Patch 13** (`printing_context_mac.mm`): M140 removed `USE_CUPS` feature check
  — took M140 upstream side (macOS printing, not carbonyl-critical)

#### Build fixes for M140 API drift

- **Skia `drawPoints`**: signature changed from `(PointMode, size_t, const SkPoint[], const SkPaint&)`
  to `(PointMode, SkSpan<const SkPoint>, const SkPaint&)` — updated in `text_capture.cc`
- **Skia `getRelativeTransform`**: now returns `SkM44` instead of `SkMatrix` — added
  `.asM33()` conversion in `text_capture.cc`
- **`HeadlessWebContentsImpl`**: `OnVisibilityChanged()` hides `WebContentsObserver`
  overload — added `using` declaration in header
- **`Font::DrawText(TextRun)`**: overloads removed from `font.h` in M140 — re-added
  carbonyl-specific declarations
- **`cc::PaintCanvas`**: incomplete type in `font.cc` — added missing include

### Chromium Upgrade: M111 → M135 — SHIPPED (Apr 2026)

A four-phase rebase of all Chromium patches across four milestones, plus two
M135-specific patches added during the final integration cycle.

| Phase | Milestone | Commit |
|-------|-----------|--------|
| Pre-flight audit | — | `2a01eef` |
| Phase 1 | M120 (120.0.6099.109) | `88d2d4d` |
| Phase 2 | M132 (132.0.6834.109) | `2293579` |
| Phase 3 | M135 (135.0.7049.84) | `c40955f` |
| M135 GN gen + CI workflows | — | `43bb745` |
| M135 Path B build fixes | — | `c22ea4f` |
| M135 Path A — blink TU restoration | — | `61b9095` |

**Final patch count**: 24 (was 21 in M132). M135 added three patches:

| Patch | Purpose |
|-------|---------|
| 0022 | Remove stale `:blink` GN dep from `blink/renderer/platform/BUILD.gn` (artifact of patch 0012/0013 mismatch) |
| 0023 | Path B build fixes — restore `Dispose()` definition and multiple M135 API drift fixes (b64 text capture re-enabled by patch 0024) |
| 0024 | Path A — allow `//carbonyl/src/blink:text_capture` to depend on blink internals; restores `--carbonyl-b64-text` mode via a dedicated blink TU |

**Runtime tarball**: published to Gitea releases as
[`runtime-34c55fd42862fd1c`](https://git.integrolabs.net/roctinam/carbonyl/releases/tag/runtime-34c55fd42862fd1c)
(x86_64-unknown-linux-gnu).

#### Key technical changes across the rebase

- **`headless_screen.{h,cc}`**: migrated to M135's `HeadlessScreenInfo`
  multi-display constructor while preserving Carbonyl DPI injection via
  `carbonyl::Bridge::GetDPI()`. `IsNaturalPortrait` moved from protected to
  public so the headless orientation delegate can call it externally.
- **`SoftwareOutputDeviceProxy`**: removed from upstream in M135; patch 13
  restores it into `components/viz/service/display_embedder/`. A Carbonyl-owned
  replacement (`carbonyl/src/viz/CarbonylSoftwareOutputDevice`) is also added
  for forward compatibility. Updated for the M135 `CreatePlatformCanvasWithPixels`
  signature (added `bytes_per_row` parameter).
- **Skia patches dropped** (M120): both former Skia patches superseded by
  in-tree changes; WebRTC GIO patch replaced by `rtc_use_pipewire=false`
- **`//build:chromeos_buildflags`** removed across M120+: dropped from all
  patch diffs
- **`compositor.h`**: M135 added `ExternalBeginFrameControllerClientFactory`;
  kept alongside Carbonyl's `CompositorDelegate`
- **GN args**: `enable_ppapi`, `enable_rust_json`, `enable_component_updater`
  removed (no longer exist in M135). Several feature flags
  (`enable_screen_ai_service`, `enable_speech_service`, `enable_pdf`,
  `enable_printing`, `enable_plugins`, `enable_browser_speech_service`,
  `enable_webui_certificate_viewer`) left at their platform defaults
  because setting them `false` triggers file-level GN asserts in
  `chrome/test/BUILD.gn` during gn gen.
- **`content::NativeWebKeyboardEvent`** moved to `input::` namespace under
  `components/input/native_web_keyboard_event.h`
- **`FontFamily::SetFamily()`** removed; use the constructor directly
- **`ScriptPromiseResolverBase::Dispose()`**: header still declares it
  unconditionally under `DCHECK_IS_ON()`, so the carbonyl patch's `#if 0`
  removal of the definition broke linking. Restored as an empty body.
- **C++20 `[=]` capture deprecation**: implicit `this` captures replaced
  with explicit `[=, this]` in `render_frame_impl.cc` and `headless_browser_impl.cc`

### Restored: Experimental b64 text-capture mode (M135+) — Path A per #28

The optional `--carbonyl-b64-text` mode is **restored** in M135 builds via a
structural refactor. It was temporarily disabled in the initial M135 ship
(Path B, [#27](https://git.integrolabs.net/roctinam/carbonyl/issues/27)) and
re-enabled by Path A ([#28](https://git.integrolabs.net/roctinam/carbonyl/issues/28),
landed in `61b9095` and documented in `25bb749`).

**Why Path B was needed first**: In M135, including
`third_party/blink/renderer/core/*` headers from a non-blink TU
(`content/renderer/render_frame_impl.cc`) triggers an Oilpan/cppgc template
cascade via Blink's `kCustomizeSupportsUnretained<T>` partial specialization,
which flows through `base::SequenceBound<T>::Storage::Destruct`'s type-erased
`void*` allocator and hard-errors on `sizeof(void)`.

**Path A fix**: Text capture now lives in a dedicated blink translation unit
under `src/blink/text_capture.{h,cc}` (in this repo, symlinked into
`chromium/src/carbonyl/src/blink/`) compiled as
`//carbonyl/src/blink:text_capture`. The new TU is built with `INSIDE_BLINK`
naturally, so the cppgc cascade vanishes — it never instantiates
`SequenceBound<T>` with a void allocator. The content-side call site is now a
thin entry point into the blink TU. Patch 0024 grants the new target
visibility into the relevant blink GN targets.

**Impact**: Both bitmap rendering (default) and `--carbonyl-b64-text` are
functional on M135. Path A is also the gating dependency that unblocks any
Chromium rebase past M135.

### CI Infrastructure (Apr 2026) — `43bb745`

- **`.gitea/workflows/check.yml`** — fast `cargo check`, `clippy`, and library
  tests on every push to main. Pinned to `runs-on: titan` (the build host).
- **`.gitea/workflows/build-runtime.yml`** — full Chromium build and runtime
  upload via `workflow_dispatch` or on patch file changes. Builds
  `headless_shell`, packages via `copy-binaries.sh`, uploads to Gitea releases
  via `runtime-push.sh`. Pinned to `titan`.
- **`build/Dockerfile.builder`** — builder image (Ubuntu 22.04 + Rust + ninja
  + cross-compile toolchains + Chromium runtime deps). Comment header
  documents that all CI runs on `titan` exclusively.

### Runtime Distribution Migration (Apr 2026) — `eb285c6`

- Migrated runtime distribution from dead CDN (`carbonyl.fathy.fr`) to
  Gitea releases API on `roctinam/carbonyl`
- `scripts/runtime-push.sh`: rewritten to create/update Gitea releases via
  `curl`, tagged `runtime-<hash>`, idempotent re-upload
- `scripts/runtime-pull.sh`: rewritten to download from Gitea releases with
  redirect support

### Automation Layer (Apr 2026)

A Python browser automation layer for agent testing pipelines, built on PTY +
`pyte` terminal emulation:

#### 🚀 Features

- **`automation/browser.py`** — `CarbonylBrowser` class: spawns carbonyl via
  PTY, feeds bytes to `pyte` screen buffer, returns clean text (`f1ae590`)
- **Session management** (`automation/session.py`): persistent Chromium
  user-data-dir sessions with fork, snapshot/restore, and live-instance
  detection (`565b81d`)
- **Persistent daemon** (`automation/daemon.py`): background browser process
  with Unix domain socket; callers reconnect without restarting Chromium,
  preserving auth cookies and page state (`72590a2`)
- **`ScreenInspector`** (`automation/screen_inspector.py`): coordinate
  visualization toolkit with rulers, annotation, crosshair, dot-map, and
  LLM-friendly region summaries (`6331195`)
- **Mouse path simulation** — `mouse_move()` + `mouse_path()` for bot-sensor
  entropy (Akamai Bot Manager mousemove requirement) (`15f0aa8`)
- **USPS PO Box smoke test** (`automation/usps_pobox.py`): end-to-end login
  and account data retrieval (`eb285c6`)

#### 🐛 Bug Fixes

- Suppress `navigator.webdriver` via `AutomationControlled` flag (`c3e08f8`)
- Spoof Firefox User-Agent and disable HTTP/2 to defeat Akamai server-side
  bot classifier (`cba5bd4`)
- Fix `click_on()` — was broken in daemon mode; now uses `find_text()` and
  clicks center of matched text (`8e4fb3e`)

### Build (Apr 2026)

- **`scripts/build-local.sh`**: pull pre-built Chromium runtime (~75 MB) and
  compile `libcarbonyl.so` from Rust (~10 s); no full Chromium build needed
  (`567f40e`)
- GN args: remove `enable_ppapi` and `enable_rust_json` (obsolete in M135)
  (`2a01eef`)
- Add `third_party/google_benchmark/buildconfig.gni` (missing from `gclient
  sync`, required by WebRTC `rtc_base`) (`2583377`)

---

## [0.0.3] - 2023-02-18

### 🚀 Features

- Add `--help` and `--version` ([#105](https://github.com/fathyb/carbonyl/issues/105))
- Add logo and description to `--help` ([#106](https://github.com/fathyb/carbonyl/issues/106))
- Use Cmd instead of Alt for navigation shortcuts ([#109](https://github.com/fathyb/carbonyl/issues/109))
- Enable h.264 support ([#103](https://github.com/fathyb/carbonyl/issues/103))
- Introduce quadrant rendering ([#120](https://github.com/fathyb/carbonyl/issues/120))

### 🐛 Bug Fixes

- Fix arguments parsing ([#108](https://github.com/fathyb/carbonyl/issues/108))
- Fix missing module error on npm package ([#113](https://github.com/fathyb/carbonyl/issues/113))
- Enable threaded compositing with bitmap mode
- Fix idling CPU usage ([#126](https://github.com/fathyb/carbonyl/issues/126))
- Package proper library in binaries ([#127](https://github.com/fathyb/carbonyl/issues/127))

### 📖 Documentation

- Update download links
- Fix commit_preprocessors url ([#102](https://github.com/fathyb/carbonyl/issues/102))
- Add `--rm` to Docker example ([#101](https://github.com/fathyb/carbonyl/issues/101))

## [0.0.2] - 2023-02-09

### 🚀 Features

- Better true color detection
- Linux support
- Xterm title
- Hide stderr unless crash
- Add `--debug` to print stderr on exit ([#23](https://github.com/fathyb/carbonyl/issues/23))
- Add navigation UI ([#86](https://github.com/fathyb/carbonyl/issues/86))
- Handle terminal resize ([#87](https://github.com/fathyb/carbonyl/issues/87))

### 🐛 Bug Fixes

- Parser fixes
- Properly enter tab and return keys
- Fix some special characters ([#35](https://github.com/fathyb/carbonyl/issues/35))
- Improve terminal size detection ([#36](https://github.com/fathyb/carbonyl/issues/36))
- Allow working directories that contain spaces ([#63](https://github.com/fathyb/carbonyl/issues/63))
- Do not use tags for checkout ([#64](https://github.com/fathyb/carbonyl/issues/64))
- Do not checkout nacl ([#79](https://github.com/fathyb/carbonyl/issues/79))
- Wrap zip files in carbonyl folder ([#88](https://github.com/fathyb/carbonyl/issues/88))
- Fix WebGL support on Linux ([#90](https://github.com/fathyb/carbonyl/issues/90))
- Fix initial freeze on Docker ([#91](https://github.com/fathyb/carbonyl/issues/91))

### 📖 Documentation

- Upload demo videos
- Fix video layout
- Fix a typo ([#1](https://github.com/fathyb/carbonyl/issues/1))
- Fix a typo `ie.` -> `i.e.` ([#9](https://github.com/fathyb/carbonyl/issues/9))
- Fix build instructions ([#15](https://github.com/fathyb/carbonyl/issues/15))
- Add ascii logo
- Add comparisons ([#34](https://github.com/fathyb/carbonyl/issues/34))
- Add OS support ([#50](https://github.com/fathyb/carbonyl/issues/50))
- Add download link
- Fix linux download links
- Document shared library
- Fix a typo (`know` -> `known`) ([#71](https://github.com/fathyb/carbonyl/issues/71))
- Add license

### Build

- Various build system fixes ([#20](https://github.com/fathyb/carbonyl/issues/20))

