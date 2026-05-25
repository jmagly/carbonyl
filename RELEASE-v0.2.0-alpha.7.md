# Carbonyl v0.2.0-alpha.7

Feature + hardening release on top of `v0.2.0-alpha.6` (M148). Adds the macOS
Apple Silicon build path, matures the `--dump-text` headless-extraction mode,
fixes terminal/X11 rendering, and hardens the runtime build/release pipeline.
The Chromium patch stack grows from 26 to 30 patches.

## Highlights

### macOS Apple Silicon (`aarch64-apple-darwin`) — new build target

Carbonyl now builds natively on Apple Silicon with **Command Line Tools only**
(no full Xcode). The build path is formalized and reproducible:

- `chromium/patches/chromium/0030-macos-build-fixes.patch` — three mac-only
  source fixes that ship latent on Linux because they live inside `IS_MAC`
  blocks: a CLT SDK-layout fallback in `build/mac/find_sdk.py`, an orphan
  `#endif` left by patch 0013 in `printing_context_mac.mm`, and a
  `device::GeolocationSystemPermissionManager` forward declaration in
  `headless_browser_impl.h` (M148 dropped the include a prior patch relied on).
- `src/browser/args.macos.gn` — the mac gn arg set (static ANGLE + SwiftShader,
  `mac_sdk_min=26.0`, CLT-only flags). `mac_deployment_target` stays 12.0, so the
  runtime runs on macOS 12+.
- `scripts/build-macos.sh` — self-contained SSH-driven build+package orchestrator.
- `docs/ci-runner-mutsu.md` — the macOS build-host runbook.

Validated end-to-end on Apple Silicon: `./carbonyl --version` →
`Carbonyl 0.2.0-alpha.3`, `Mach-O 64-bit executable arm64`. The Linux build is
untouched — the mac path is entirely additive. Closes [#109](https://github.com/jmagly/carbonyl/issues/109).

The runtime build smoke test is now arch-aware: a cross-compiled binary is
validated via `file` rather than executed, so non-native target builds no longer
break at the smoke step ([#110](https://github.com/jmagly/carbonyl/issues/110)).
Full public-asset automation for macOS continues under the multi-arch tracker
[#67](https://github.com/jmagly/carbonyl/issues/67).

### `--dump-text` headless text extraction

The text-only extraction mode introduced this cycle skips the terminal renderer
entirely and emits page text on stdout — built for scraping and LLM pipelines:

- `--dump-text` (default), `--dump-text=accessibility`, `--dump-text=raw-dom`
  ([#88](https://github.com/jmagly/carbonyl/issues/88)).
- An accessibility-tree FFI bridge backs `--dump-text=accessibility`
  ([#98](https://github.com/jmagly/carbonyl/issues/98)).
- Extraction now performs an ordered Chromium shutdown instead of `std::_Exit`,
  so cookies and on-disk state flush cleanly on exit
  ([#93](https://github.com/jmagly/carbonyl/issues/93)).
- Navigation failures (DNS, connection refused, TLS) return **exit code 6** with
  empty stdout instead of dumping Chromium's error page
  ([#91](https://github.com/jmagly/carbonyl/issues/91)).

### Rendering fixes

- Near-uniform quadrants collapse to a single color, removing speckle on
  large flat regions ([#79](https://github.com/jmagly/carbonyl/issues/79)).
- Terminal-render mode uses the sample window as the CSS viewport, so layout
  matches the rendered cell grid ([#100](https://github.com/jmagly/carbonyl/issues/100)).
- `--viewport` is honored in the X11 ozone screen path (patch 0029)
  ([#101](https://github.com/jmagly/carbonyl/issues/101)).

### UI

- `--chrome-rows=N` stacks the URL/chrome bar across N terminal rows, giving the
  address bar more room on wide terminals ([#80](https://github.com/jmagly/carbonyl/issues/80)).

### Build, CI, and release-pipeline hardening

- Rust sources are now part of the runtime-hash inputs, so a pure-`libcarbonyl`
  fix gets its own runtime tag instead of colliding with the prior build
  ([#92](https://github.com/jmagly/carbonyl/issues/92)).
- A `validate-patches` workflow verifies the Chromium patch stack pre-merge
  ([#103](https://github.com/jmagly/carbonyl/issues/103)); patch 0028 was rewritten
  against verified source context ([#102](https://github.com/jmagly/carbonyl/issues/102)).
- `build-runtime.yml` gained workflow-level concurrency, stale-lock self-heal,
  pipefail-safe lock probes, and holder-aware release
  ([#83](https://github.com/jmagly/carbonyl/issues/83),
  [#85](https://github.com/jmagly/carbonyl/issues/85),
  [#86](https://github.com/jmagly/carbonyl/issues/86),
  [#106](https://github.com/jmagly/carbonyl/issues/106)).
- Post-#99 main-branch CI failures repaired and `libcarbonyl` exposed to the
  build helpers ([#104](https://github.com/jmagly/carbonyl/issues/104),
  [#105](https://github.com/jmagly/carbonyl/issues/105)).

## What's in the runtime

Runtime hash `e38a57d2afdbe7e7`.

Linux amd64, both Ozone variants:

- `carbonyl-0.2.0-alpha.7-x86_64-unknown-linux-gnu.tgz` — `headless` ozone (default; pure-terminal)
- `carbonyl-0.2.0-alpha.7-x11-x86_64-unknown-linux-gnu.tgz` — `x11` ozone (terminal + X-mirror; for trusted-input mode)

macOS Apple Silicon (new):

- `carbonyl-0.2.0-alpha.7-aarch64-apple-darwin.tgz` — `headless` ozone, built on
  the `mutsu` host (see `docs/ci-runner-mutsu.md`)

Each tarball ships with a `.sha256` companion.

## Upgrade notes

- No CLI breaking changes. `--dump-text`, `--chrome-rows`, and the navigation
  exit codes are additive.
- The runtime hash changed (`e38a57d2afdbe7e7`), so `runtime-pull.sh` fetches a
  fresh runtime — this is expected after the Rust-sources hash-input change (#92)
  and the new mac patch/args.
