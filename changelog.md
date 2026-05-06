# Changelog

All notable changes to this project will be documented in this file.

## [0.2.0-alpha.4] - 2026-05-06

### 🚀 Features

- Opt-in eager cookie SQLite flush via CLI

### 🐛 Bug Fixes

- Forward --carbonyl-cookie-flush-interval-ms to child processes

### Ci

- Ozone_platform=both — single tag push ships all variants
- Pin builder image via .gitea/builder-image-pin
- Test-text-parity.yml — wire W0.6 parity harness into a workflow
- Add concurrency group to prevent self-racing

### Test

- W0.6 text-render parity harness + 3 fixtures + report

## [0.2.0-alpha.3] - 2026-04-29

### 🚀 Features

- X mirror surface for compositor frames (CARBONYL_X_MIRROR)
- --ozone flag on runtime-pull.sh and runtime-push.sh

### 🐛 Bug Fixes

- Use github.actor (Gitea-aliased) not gitea.actor for docker login
- Configure git safe.directory for bind-mounted repos
- Set CI git user.email/user.name in builder image + workflow
- Reset chromium/src to clean state before patches apply
- Abort stale git am/rebase state before reset
- Force-reset repos instead of stash-then-checkout
- Skip patches.sh apply when patches dir empty
- Mount workspace at host-matching path to satisfy symlinks
- Remove phantom //carbonyl/src/browser:carbonyl dep
- Restore trailing newline on 0001-Add-Carbonyl-library.patch
- Redirect phantom :carbonyl fix to patch 0013
- Fix double out/ path bug in build steps
- Drop stray CARBONYL_SKIP_CARGO_BUILD= positional arg
- Pass -j NINJA_JOBS through build.sh to ninja
- Add Chromium build deps — gperf, bison, flex, pkg-config
- Regenerate patch 0013 from grissom working tree
- Add 0025-fix-m147-finalize for M147 API drift
- Add libgbm1, libegl1, libgl1, libxkbcommon0 runtime libs
- Include ANGLE + SwiftShader runtime libs in ninja targets
- Env.sh safe under set -u
- Print HTTP response body on release-create failure
- Satisfy Chromium clang plugins in x_mirror.cc
- Resolve clippy 1.91 backlog and unblock check.yml
- Separate runtime tags per ozone_platform variant

### 📖 Documentation

- Land design docs drafted 2026-04-02
- Land SDLC corpus for bot-detection initiative
- Reframe Phase 3 as owned fingerprint registry
- Add roadmap + CI plan; adopt jmagly/wreq fork
- Land Gitea Actions + builder-container CI/CD plan
- Flip wreq to Gitea-primary; corpus repo; containers
- ADR-002 trusted input approach (draft, pending Phase 0)
- Pivot to x11 Ozone + Xorg-in-container
- Phase 0 W0.1 patch paper-audit for x11 Ozone compatibility
- Cascade W0.1 audit findings
- Update post-pivot labeling for trusted-input path
- Runtime modes — terminal, x11+uinput, x11+x-mirror
- Secrets inventory + rotation + leak-response playbook

### Ci

- Migrate build-runtime to container; split build-builder; add titan runbook
- Pin Rust to 1.91.0 and containerize check.yml
- Run dual-output validation for x11 builds
- Mirror.yml — one-way sync origin → github
- Release.yml — publish v* tag to Gitea + GitHub releases

### Test

- Dual-output validation harness

## [0.2.0-alpha.2] - 2026-04-17

### 🐛 Bug Fixes

- SDK-driven CSS viewport via --viewport, closes [#37](https://github.com/fathyb/carbonyl/issues/37)

### 📖 Documentation

- Scrub internal repo/host references from v0.2.0-alpha.1 notes
- Scrub internal repo/host refs and nudge logo alignment

## [0.2.0-alpha.1] - 2026-04-15

### 🚀 Features

- Path A — extract carbonyl text capture into a blink TU

### 🐛 Bug Fixes

- Apply M120 compile fixes to carbonyl src and update patches
- Gn gen fixes, CI workflows, and builder Dockerfile
- Replace VLA with std::vector in renderer.cc
- Path B — disable b64 text capture, M135 build is green
- Replace EndMarkerZulu assertion with Foxtrot (viewport fit)

### 📖 Documentation

- Add M111→M135 upgrade plan
- Update MAINTENANCE.md and changelog for M135 upgrade
- Update changelog, readme, and MAINTENANCE for M135 ship
- Update cross-layer audit for post-Path-A state
- Update changelog, readme, and MAINTENANCE for Path A landing
- Update changelog, readme, and MAINTENANCE for M140 rebase
- Update changelog, readme, and MAINTENANCE for M147 rebase
- Surface carbonyl-agent + carbonyl-fleet links prominently
- Normalize structure to AIWG gold-standard template

### Release

- First alpha of the roctinam/carbonyl fork

### Test

- Add b64 text-capture smoke test

## [0.1.0] - 2026-04-03

### 🚀 Features

- Add Python browser automation layer
- Add local build pipeline and maintenance docs
- Add session management and headless flags
- Persistent headless browser daemon with socket reconnect
- Add ScreenInspector coordinate visualization toolkit
- Add mouse_move() and mouse_path() for bot-sensor entropy
- Improve click targeting and coordinate consistency

### 🐛 Bug Fixes

- Link to Chromium sysroot libs on Linux ([#134](https://github.com/fathyb/carbonyl/issues/134))
- Suppress navigator.webdriver via AutomationControlled flag
- Spoof Firefox UA and disable HTTP/2 for bot-detection evasion

### 📖 Documentation

- Update download links
- Add full SDLC elaboration artifacts for automation layer

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


