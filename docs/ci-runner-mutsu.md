# macOS build host: mutsu (aarch64-apple-darwin)

Carbonyl's macOS ARM runtime (`aarch64-apple-darwin`) is built on **mutsu**, an
Apple Silicon Mac. Unlike titan (see [ci-runner-titan.md](ci-runner-titan.md)),
mutsu is **not** a Gitea Actions runner — the fleet does not run the Gitea
runner on macOS (an RPC issue), so the mac build is driven over SSH. CI wiring
can come later; today an operator (or an agent with SSH access) runs one script.

Tracks: roctinam/carbonyl #109 (parent #67).

## Host facts

| | |
|---|---|
| OS | macOS 26.x (Darwin 25.x), Apple Silicon |
| Toolchain | Apple clang (**Command Line Tools only — no full Xcode.app**) |
| SDK | current macOS SDK under `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` |
| Build volume | `/Volumes/build` — the boot volume `/` is too small for a Chromium checkout (~150 GB); **always build under `/Volumes/build`** |
| Workspace | `/Volumes/build/carbonyl` |

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

```bash
cd /Volumes/build/carbonyl
caffeinate -dimsu nohup bash scripts/build-macos.sh > build-macos.log 2>&1 &
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

The asset lands on the `runtime-<hash>` release (same hash scheme as Linux).
Verify with `scripts/runtime-pull.sh arm64 macos`.

## Notes

- **CLT vs full Xcode**: the headless software-rendering build needs neither
  full Xcode nor the Metal toolchain. `args.macos.gn` sets `use_clang_modules=false`
  (15.x SDK lacks DarwinFoundation modulemaps) and `angle_enable_metal=false`
  (`xcrun metal` is Xcode-only). ANGLE links statically; the runtime ships
  SwiftShader for software GL.
- **SDK version**: `args.macos.gn` sets `mac_sdk_min="26.0"` to build against the
  current SDK (M148 uses 26.x-only symbols). `mac_deployment_target` stays 12.0,
  so the runtime runs on macOS 12+.
