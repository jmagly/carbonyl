# Changelog

All notable changes to this project will be documented in this file.

---

## [Unreleased] — jmagly/carbonyl fork

This section covers work done in the `jmagly/carbonyl` fork since the upstream
(`fathyb/carbonyl`) became inactive in February 2023. The fork maintains
Carbonyl for use in automated agent testing pipelines and upgrades the
Chromium base through M135.

### Chromium Upgrade: M111 → M135 (Apr 2026)

A four-phase rebase of all 21 Chromium patches across four milestones:

| Phase | Milestone | Commit |
|-------|-----------|--------|
| Pre-flight audit | — | `2a01eef` |
| Phase 1 | M120 (120.0.6099.109) | `88d2d4d` |
| Phase 2 | M132 (132.0.6834.109) | `2293579` |
| Phase 3 | M135 (135.0.7049.84) | `c40955f` |

Key technical changes across the rebase:

- **`headless_screen.{h,cc}`**: migrated to M135's `HeadlessScreenInfo`
  multi-display constructor while preserving Carbonyl DPI injection via
  `carbonyl::Bridge::GetDPI()`
- **`SoftwareOutputDeviceProxy`**: removed from upstream in M135; patch 13
  restores it into `components/viz/service/display_embedder/`. A Carbonyl-owned
  replacement (`carbonyl/src/viz/CarbonylSoftwareOutputDevice`) is also added
  for forward compatibility.
- **Skia patches dropped** (M120): both former Skia patches superseded by
  in-tree changes; WebRTC GIO patch replaced by `rtc_use_pipewire=false`
- **`//build:chromeos_buildflags`** removed across M120+: dropped from all
  patch diffs
- **`compositor.h`**: M135 added `ExternalBeginFrameControllerClientFactory`;
  kept alongside Carbonyl's `CompositorDelegate`
- **GN args**: `enable_ppapi` and `enable_rust_json` removed (no longer exist
  in M135)

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

