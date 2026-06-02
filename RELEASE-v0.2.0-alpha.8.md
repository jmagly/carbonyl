# Carbonyl v0.2.0-alpha.8

Small feature + release-engineering update on top of `v0.2.0-alpha.7` (M148).
`--dump-text=accessibility` now emits the real accessibility tree, and the
release pipeline gained automated macOS asset staging. No Chromium patch
changes — the patch stack stays at 30.

## Highlights

### `--dump-text=accessibility` now emits the real accessibility tree

Previously this mode fell back to `document.body.innerText` with a warning,
because the backing FFI hadn't been wired. It now calls the browser-process
accessibility-tree snapshot — the `AccessibilityHandler` FFI
([#4](https://github.com/jmagly/carbonyl/issues/4) /
[#98](https://github.com/jmagly/carbonyl/issues/98)), installed unconditionally
by Chromium patch 0028 — and emits a role / name / value / landmark JSON tree on
stdout, with no JavaScript eval. On any failure path (AX mode off, no bound
WebContents) it emits the sentinel `{"error":"no_tree"}`.
([#90](https://github.com/jmagly/carbonyl/issues/90))

The `--dump-text` navigation-failure log no longer double-prefixes `net::`
(`net::ErrorToString` already prepends it).
([#97](https://github.com/jmagly/carbonyl/issues/97))

### Release pipeline — automated macOS asset staging

`release.yml` now stages and mirrors the `aarch64-apple-darwin` runtime with no
manual steps: it pulls `aarch64-apple-darwin.tgz` from the shared
`runtime-<hash>` release, stages `carbonyl-<version>-aarch64-apple-darwin.tgz`
(+ `.sha256`), and the existing GitHub-mirror loop carries it. A default-on
`include_macos` toggle fails the release loudly if the macOS runtime asset is
missing — rather than silently shipping Linux-only; set `include_macos=false`
for an interim Linux-only cut.
([#113](https://github.com/jmagly/carbonyl/issues/113),
[#117](https://github.com/jmagly/carbonyl/issues/117))

### Multi-arch status

`aarch64-unknown-linux-gnu` (Linux arm64) is **not** in this release. titan is
x86_64-only and mutsu's 16 GiB RAM makes a VM-hosted Chromium build impractical,
so arm64-linux is pending dedicated arm64 build hardware
([#116](https://github.com/jmagly/carbonyl/issues/116); tracker
[#67](https://github.com/jmagly/carbonyl/issues/67)).

## What's in the runtime

Runtime hash `283ca65ffeeaa2dc`.

Linux amd64, both Ozone variants:

- `carbonyl-0.2.0-alpha.8-x86_64-unknown-linux-gnu.tgz` — `headless` ozone (default; pure-terminal)
- `carbonyl-0.2.0-alpha.8-x11-x86_64-unknown-linux-gnu.tgz` — `x11` ozone (terminal + X-mirror; for trusted-input mode)

macOS Apple Silicon:

- `carbonyl-0.2.0-alpha.8-aarch64-apple-darwin.tgz` — `headless` ozone, built on the `mutsu` host (see `docs/ci-runner-mutsu.md`)

Each tarball ships with a `.sha256` companion.

## Upgrade notes

- No CLI breaking changes. The **`--dump-text=accessibility` output format
  changed** from plain innerText to the AX JSON tree — callers parsing that mode
  should now expect JSON (the default `--dump-text` and `--dump-text=raw-dom`
  modes are unchanged).
- The runtime hash changed (`283ca65ffeeaa2dc`) because the dump-text bridge
  source changed, so `runtime-pull.sh` fetches a fresh runtime.
