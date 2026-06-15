# Packaging

Native install packages for Carbonyl (#129, [ADR-003](../docs/adr-003-native-install-packages.md)).
User-facing install instructions live in [docs/install.md](../docs/install.md);
this file is for maintainers.

## What gets built

| Format | Script | Runs on | In release via |
|---|---|---|---|
| `.deb`, `.rpm` | `scripts/package-linux.sh` (nfpm) | titan / Linux | `release.yml` (automatic) |
| `.AppImage` | `scripts/package-linux.sh` (appimagetool) | titan / Linux | `release.yml` (automatic) |
| `.pkg`, `.dmg` (unsigned) | `scripts/package-macos.sh` (pkgbuild/hdiutil) | mutsu / macOS | `scripts/mutsu-package-macos.sh` (operator, release-time) |

Both `package-*.sh` scripts are host-agnostic: they take a runtime payload dir
(the contents of `build/pre-built/<triple>/`, i.e. what the runtime tarball
contains) plus a `--version`, and emit packages to `--out`.

## Install layout

- **Linux:** payload → `/usr/lib/carbonyl/`; launcher → `/usr/bin/carbonyl`
  (`packaging/linux/carbonyl.launcher`, sets `LD_LIBRARY_PATH`). Desktop entry
  `packaging/linux/carbonyl.desktop`, icon `packaging/linux/carbonyl.svg`
  (rasterized to a 256×256 PNG when `rsvg-convert`/`convert` is present).
- **macOS:** payload → `/usr/local/carbonyl/`; pkg postinstall
  (`packaging/macos/postinstall`) symlinks `/usr/local/bin/carbonyl`. The `.dmg`
  wraps the `.pkg` + `packaging/macos/GATEKEEPER.txt`.

## Pinned tools (`scripts/package-linux.sh`)

Fetched with version + sha256 verification if not already on `PATH`
(ci-action-pinning). CI builders should preinstall them
(`dev-ci-self-contained`; tracked in #129).

| Tool | Version | sha256 |
|---|---|---|
| nfpm | 2.41.3 | `22aa6d3bc2ec239d62d3d190bcb036a47f2b24e0c3c6edfccebb6a55fbb2078e` |
| appimagetool | 1.9.1 | `ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0` |

## Dependencies (Linux)

Declared per format in `package-linux.sh` from `ldd` of the headless binary.
deb uses `libasound2t64 | libasound2` to span the Ubuntu 24.04 t64 transition.
Supported targets: Debian 12+/Ubuntu 22.04+ (deb), Fedora 38+/openSUSE (rpm).

## Building locally (test/debug only)

Release-grade artifacts are produced in CI / on mutsu. To smoke-test the scripts:

```bash
# Linux — from a runtime payload dir
bash scripts/package-linux.sh --payload build/pre-built/x86_64-unknown-linux-gnu \
  --version 0.2.0-alpha.9 --arch amd64 --out build/packages-native

# macOS — on mutsu, with scratch on the external volume (boot disk is small)
TMPDIR=/Volumes/build/.carbonyl-scratch/tmp \
  bash scripts/package-macos.sh --payload build/pre-built/aarch64-apple-darwin \
  --version 0.2.0-alpha.9 --arch arm64 --out /Volumes/build/.carbonyl-scratch/pkgout
```

## macOS at release time

`scripts/mutsu-package-macos.sh --version <v>` SSHes to mutsu, fast-forwards
`main`, ensures the macOS runtime payload is present (pulls it if needed), builds
the unsigned `.pkg`/`.dmg` on the external volume, streams them back, and uploads
`carbonyl-<v>-macos-arm64.{pkg,dmg}` (+ `.sha256`) to the versioned Gitea release
and (if `GH_MIRROR_TOKEN` is set) the GitHub mirror. Run it after `release.yml`
has created the versioned release. See
[docs/ci-runner-mutsu.md](../docs/ci-runner-mutsu.md).

## Known follow-ups

- Replace the placeholder icon (`packaging/linux/carbonyl.svg`) with the real logo.
- Add nfpm + appimagetool to the `carbonyl-builder` image (self-contained CI).
- Sign + notarize the macOS installer once an Apple Developer ID exists.
- Linux arm64 packages once #116 publishes that runtime.
- Optional `-x11` Linux package; optional apt/dnf repo hosting.
