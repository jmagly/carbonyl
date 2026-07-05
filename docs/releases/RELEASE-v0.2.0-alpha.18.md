# Carbonyl v0.2.0-alpha.18

Chromium runtime refresh on top of `v0.2.0-alpha.17`. Carbonyl now tracks
Chromium `150.0.7871.47` (M150), with the Chromium, Skia, and WebRTC pins
updated from the M150 DEPS graph and the Chromium patch stack regenerated.

## Highlights

### Chromium M150 runtime

Google promoted Chrome 150 to the stable desktop channel on June 30, 2026, and
ChromiumDash showed the matching desktop stable tag used here:
`150.0.7871.47`.

Runtime source pins:

- Chromium: `0c3cca15d78645281db2d339b2dc3d6fad4ee90a`
- Skia: `14d05ec761901b6e9e9193af8b347ab3a7f6fed0`
- WebRTC: `1f975dfd761af6e5d76d28333191973b258d82a8`

The Carbonyl patch stack is now 35 patches. Most patches are regenerated for
M150 context drift; patch 0035 adds the logging include needed by the restored
viz software output proxy in M150.

### Build and CI hardening

- X11 runtime builds now set the matching ANGLE and WebRTC X11 GN switches in
  both CI and the mutsu Linux arm64 driver.
- Linux native packages now declare the X11 loader libraries required by the
  x11 Ozone variant, including `libXcomposite.so.1`; the container image build
  smokes this by running `carbonyl --version` immediately after installing the
  `.deb`.
- The direct `ninja` build step exports `LD_LIBRARY_PATH` for generated helper
  binaries that load `libcarbonyl.so`.
- Patch validation syncs the branch `.gclient`, fetches the target Chromium tag
  when needed, and clears stale host patch directories before rsync.
- The text parity harness avoids a `pipefail`/SIGPIPE abort when extracting
  terminal frames, so parity failures now reflect rendering differences rather
  than a shell pipeline race.

## What's in the runtime

Runtime hash `350d2b8ba8e5ab72`.

Linux amd64, both Ozone variants:

- `carbonyl-0.2.0-alpha.18-x86_64-unknown-linux-gnu.tgz` — `headless` ozone
  (default; pure-terminal)
- `carbonyl-0.2.0-alpha.18-x11-x86_64-unknown-linux-gnu.tgz` — `x11` ozone
  (terminal + X-mirror; for trusted-input mode)

Linux native packages:

- `carbonyl_0.2.0~alpha.18_amd64.deb`
- `carbonyl-0.2.0~alpha.18-1.x86_64.rpm`
- `carbonyl-0.2.0-alpha.18-x86_64.AppImage`

Each artifact ships with a `.sha256` companion. macOS and Linux arm64 assets are
not included unless their matching `runtime-350d2b8ba8e5ab72` platform tarballs
are published before a release re-run.

## Validation

- Local patch/apply/build smoke:
  - `bash scripts/gclient.sh sync`
  - `bash scripts/patches.sh apply`
  - `bash scripts/audit-cross-layer.sh`
  - `bash scripts/gn.sh gen out/Default --args="$(cat src/browser/args.gn)"`
  - `bash scripts/build.sh Default amd64 -j 8`
  - `bash scripts/copy-binaries.sh Default amd64`
  - `cargo test`
  - `bash scripts/test-b64-text.sh`
  - `CARBONYL_CDP_PORT=19333 bash scripts/test-cdp.sh`
- Gitea PR checks on `95c3cc7`: Check/Lint, Security, and Validate Patches all
  passed.
- Runtime CI: amd64 headless and x11 runtime matrix passed and published
  `runtime-350d2b8ba8e5ab72` and `runtime-x11-350d2b8ba8e5ab72`.
- Text parity: `static.html`, `css-rich.html`, and `dynamic.html` all passed
  using the published runtime hash.

## Source verification

- Chrome Releases: Stable Channel Update for Desktop, June 30, 2026:
  https://chromereleases.googleblog.com/2026/06/stable-channel-update-for-desktop_0175352312.html
- ChromiumDash releases:
  https://chromiumdash.appspot.com/releases

## Upgrade notes

- The runtime hash changed from alpha.17 because the Chromium version, patch
  stack, and GN/runtime workflow inputs changed.
- No CLI breaking changes are introduced by the M150 runtime bump.
