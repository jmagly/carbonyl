# mutsu build host: macOS arm64 and Linux arm64 dispatch

Carbonyl's macOS ARM runtime (`aarch64-apple-darwin`) is built on **mutsu**, an
Apple Silicon Mac. Unlike titan (see [ci-runner-titan.md](ci-runner-titan.md)),
mutsu is **not** a Gitea Actions runner — the fleet does not run the Gitea
runner on macOS (an RPC issue), so the mac build is driven over SSH. The
**release side is now automated**: once a macOS runtime is published to
`runtime-<hash>`, `release.yml` stages `carbonyl-<version>-aarch64-apple-darwin.tgz`
and mirrors it to GitHub with no manual steps (gated by the `include_macos`
toggle; #113 / #117). The **build trigger** is SSH-dispatched from an
authorized host using `scripts/mutsu-build-macos.sh`; mutsu itself still does
not run a Gitea Actions runner.

The same host can also dispatch the Linux ARM64 runtime
(`aarch64-unknown-linux-gnu`) through a dedicated Colima profile and separate
checkout. That path is tracked by #116 and feeds the release triple matrix in
#108.

Tracks: roctinam/carbonyl #109, #116 (parent #67).

## Host facts

| | |
|---|---|
| OS | macOS 26.x (Darwin 25.x), Apple Silicon |
| Toolchain | Apple clang (**Command Line Tools only — no full Xcode.app**) |
| SDK | current macOS SDK under `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` |
| Build volume | `/Volumes/build` — the boot volume `/` is too small for a Chromium checkout (~150 GB) and can sit at ~100% full; **always build under `/Volumes/build`**. The build scripts anchor cargo cache + temp to `/Volumes/build/.carbonyl-scratch` so nothing scratch-heavy lands on the boot disk (see "external build scratch" below). |
| macOS workspace | `/Volumes/build/carbonyl` |
| Linux arm64 workspace | `/Volumes/build/carbonyl-linux-arm64` |

## One-time setup

```bash
# 1. Rust (pinned by rust-toolchain.toml) + the mac target
rustup default 1.91.0
rustup target add aarch64-apple-darwin

# 2. Clone + sync Chromium (multi-hour; ~150 GB). Run detached under caffeinate.
cd /Volumes/build/carbonyl
caffeinate -dimsu nohup bash scripts/gclient.sh sync > gclient-sync.log 2>&1 &

# 3. Apply patches (includes 0030 macos build fixes)
bash scripts/patches.sh apply
```

## Build + package

From an authorized admin host:

```bash
bash scripts/mutsu-build-macos.sh --jobs 2
```

The SSH driver runs against `mutsu:/Volumes/build/carbonyl` by default. It
refuses to continue when the remote worktree is dirty, fetches and
fast-forwards `main`, runs `scripts/gclient.sh sync`, reapplies patches, runs
`scripts/build-macos.sh`, and smokes the resulting runtime with
`./carbonyl --version`.

Useful overrides:

```bash
MUTSU_HOST=mutsu bash scripts/mutsu-build-macos.sh --branch main --jobs 2
bash scripts/mutsu-build-macos.sh --host roctinam@mutsu --remote-dir /Volumes/build/carbonyl
```

To run directly on mutsu:

```bash
cd /Volumes/build/carbonyl
caffeinate -dimsu nohup bash scripts/build-macos.sh --jobs 2 > build-macos.log 2>&1 &
# watch: tail -f build-macos.log
```

`build-macos.sh` is self-contained — it creates the CLT accommodations at
runtime so the operator does not have to:

- **`xcodebuild` shim** — CLT has no `xcodebuild`; Chromium's `sdk_info.py` only
  needs `xcodebuild -version`.
- **python ≥ 3.10** — macOS system `python3` is 3.9 (no PEP 604) and `env.sh`
  appends depot_tools to `PATH`; the script prepends depot_tools' bootstrapped
  python 3.11 so build-time tooling works.
- **`ulimit -n 61440`** — clang opens many SDK framework headers; the default
  soft limit (256) causes "Too many open files".
- **macOS gn args** — `src/browser/args.macos.gn` (the Linux `args.gn` carries
  X11/Wayland/dbus/etc. flags gn rejects on the mac toolchain).
- **conservative parallelism** — on a 16 GiB Mac mini, the default is `-j2`.
  Passing `--jobs 2` is the documented explicit setting for predictable
  unattended builds.
- **external build scratch** — `CARGO_HOME` and `TMPDIR` are anchored to
  `<external-volume>/.carbonyl-scratch` (a sibling of the checkout, e.g.
  `/Volumes/build/.carbonyl-scratch`). mutsu's boot volume is small and can run
  100% full; cargo's default `~/.cargo` cache and the default `/var/folders`
  `TMPDIR` would otherwise write to the boot disk and fail the build with
  ENOSPC. The scratch dir is a sibling of the checkout (not inside it), so it
  never trips the driver's clean-worktree check. Override with `CARGO_HOME` /
  `CARBONYL_TMPDIR`.

Output:

- `build/pre-built/aarch64-apple-darwin/` — runtime payload
  (`carbonyl`, `libcarbonyl.dylib`, `icudtl.dat`, `v8_context_snapshot*.bin`,
  `libvk_swiftshader.dylib`)
- `build/pre-built/aarch64-apple-darwin.tgz` — tarball

## Smoke + publish

```bash
( cd build/pre-built/aarch64-apple-darwin && ./carbonyl --version )

GITEA_TOKEN="$(cat ~/.config/gitea/token)" \
  CARBONYL_OZONE_TAG=headless bash scripts/runtime-push.sh arm64
```

Or from the authorized SSH driver host:

```bash
GITEA_TOKEN="$(cat ~/.config/gitea/token)" \
  bash scripts/mutsu-build-macos.sh --jobs 2 --publish
```

The asset lands on the `runtime-<hash>` release (same hash scheme as Linux).
Verify with `scripts/runtime-pull.sh arm64 macos`.

## macOS install package (.pkg / .dmg) — #129

The unsigned macOS installer is **version-stamped**, so it is built at release
time (after a `v*` tag exists) rather than at runtime-build time. Only mutsu can
run `pkgbuild`/`hdiutil`, so this is SSH-driven like the runtime build. (Linux
`.deb`/`.rpm`/`.AppImage` are produced automatically in `release.yml` on titan.)

From an authorized admin host, after `release.yml` has created the release:

```bash
GITEA_TOKEN="$(cat ~/.config/gitea/token)" \
GH_MIRROR_TOKEN="$(cat ~/.config/github/mirror-token)" \
  bash scripts/mutsu-package-macos.sh --version 0.2.0-alpha.9 --host mutsu-agent
```

The driver fast-forwards `main` on mutsu, ensures the macOS runtime payload for
the tag's hash is present (pulling it via `runtime-pull.sh arm64 macos` if not),
runs `scripts/package-macos.sh` with **scratch + output on `/Volumes/build`**
(the boot disk is small and can run full — same reason as the build scratch
above), streams the artifacts back, and uploads
`carbonyl-<version>-macos-arm64.{pkg,dmg}` (+ `.sha256`) to the versioned Gitea
release and the GitHub mirror. Omit `GH_MIRROR_TOKEN` (or pass `--gitea-only`)
to skip the GitHub upload. The installer is unsigned (no Apple Developer ID);
see `packaging/macos/GATEKEEPER.txt` and ADR-003.

## Linux ARM64 build + publish (#116)

> **Preferred trigger: the `build-runtime-arm64.yml` CI workflow.** Dispatch it
> from the Gitea Actions UI (or `tea`) — it runs on the always-on `titan` runner
> and SSH-drives the script below, so the multi-hour build is monitored by CI and
> survives an operator-workstation reboot. Inputs: `ozone_platform`
> (headless|x11|both), `publish` (uses `BUILD_REPO_TOKEN`, like every other
> runtime publish), `preflight_only`, `ninja_jobs`, `skip_sync`. It reaches mutsu
> by building a job-local SSH config from the **`MUTSU_SSH_KEY`** secret (the
> `mutsu_automation` key) targeting `10.0.42.41` — see "mutsu SSH access" in
> `docs/ci-secrets.md`. The manual driver below stays valid for ad-hoc/debug runs
> from an authorized host.

Linux ARM64 is built in an aarch64 Linux Colima VM on mutsu. The driver builds
a local arm64 `carbonyl-builder:<commit>-arm64` image from
`build/Dockerfile.builder` because the registry-pinned builder image is
currently amd64-only. Set `MUTSU_BUILDER_IMAGE` only when an arm64 registry
image is available. The driver intentionally uses a separate repo checkout,
Colima profile, and VM-native Chromium build directory so Linux gclient/build
state cannot interfere with the macOS runtime tree.

From an authorized SSH driver host:

```bash
bash scripts/mutsu-build-linux-arm64.sh \
  --ssh-config /home/roctinam/.ssh/config \
  --jobs 2
```

Default remote resources:

| | |
|---|---|
| SSH host | `mutsu-agent` |
| Colima profile | `carbonyl-linux-arm64` |
| Colima home | `/Volumes/build/.colima` |
| Repo checkout | `/Volumes/build/carbonyl-linux-arm64` |
| Chromium build dir | `/mnt/lima-colima-carbonyl-linux-arm64/carbonyl-linux-arm64` inside the Colima VM |
| Mounts | `/Volumes/build:w` for the repo checkout; VM ext4 for Chromium `src/out` |
| CPUs / memory / disk | `8` CPUs, `12` GiB RAM, `500` GiB disk |

Do not put the Linux Chromium `src/out` tree on the macOS `/Volumes/build`
virtiofs mount. `gclient` and Chromium builds do large Git and filesystem
walks; keeping that tree on the Colima VM's ext4 disk avoids pathological
stalls while still keeping the lightweight repo checkout on `/Volumes/build`.

Publishing uses the same runtime tag as Linux amd64:

```bash
GITEA_TOKEN="$(cat ~/.config/gitea/token)" \
  bash scripts/mutsu-build-linux-arm64.sh \
    --ssh-config /home/roctinam/.ssh/config \
    --jobs 2 \
    --publish
```

The default build is headless and publishes to `runtime-<hash>`. To publish the
x11 Ozone variant required by the default release workflow, run the same driver
with `--ozone x11`; that publishes to `runtime-x11-<hash>`:

```bash
GITEA_TOKEN="$(cat ~/.config/gitea/token)" \
  bash scripts/mutsu-build-linux-arm64.sh \
    --ssh-config /home/roctinam/.ssh/config \
    --ozone x11 \
    --jobs 2 \
    --publish
```

Expected output:

- `build/pre-built/aarch64-unknown-linux-gnu/` in the repo checkout
- `build/pre-built/aarch64-unknown-linux-gnu.tgz` in the repo checkout
- Gitea release asset `runtime-<hash>/aarch64-unknown-linux-gnu.tgz`

The release workflow does not include Linux arm64 by default until this asset is
known to exist for the tag's runtime hash. Re-run `release.yml` with
`include_linux_arm64=true`; the workflow validates
`aarch64-unknown-linux-gnu.tgz` before staging and fails loudly if the asset is
missing.

## Notes

- **CLT vs full Xcode**: the headless software-rendering build needs neither
  full Xcode nor the Metal toolchain. `args.macos.gn` sets `use_clang_modules=false`
  (15.x SDK lacks DarwinFoundation modulemaps) and `angle_enable_metal=false`
  (`xcrun metal` is Xcode-only). ANGLE links statically; the runtime ships
  SwiftShader for software GL.
- **SDK version**: `args.macos.gn` sets `mac_sdk_min="26.0"` to build against the
  current SDK (M148 uses 26.x-only symbols). `mac_deployment_target` stays 12.0,
  so the runtime runs on macOS 12+.
