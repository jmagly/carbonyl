#!/usr/bin/env bash
# build-macos.sh — Build + package the Carbonyl aarch64-apple-darwin runtime on
# an Apple Silicon Mac with Command Line Tools only (no full Xcode.app). (#109)
#
# Why a separate script: macOS is not a Gitea-runner target in this fleet (the
# Mac is driven over SSH), and the Linux build.sh / copy-binaries.sh hardcode
# Linux .so graphics targets. This script encapsulates the mac-specific build
# so a future CI step (or an operator over SSH) can run one command.
#
# Prerequisites (see docs/ci-runner-mutsu.md):
#   - chromium/src synced to the pinned version:  scripts/gclient.sh sync
#   - patches applied (includes 0030 macos fixes): scripts/patches.sh apply
#   - rustup with the pinned toolchain + aarch64-apple-darwin target
#   - Command Line Tools installed (xcode-select -p -> .../CommandLineTools)
#
# Usage:
#   bash scripts/build-macos.sh [--ozone headless] [-j N]
#
# Output:
#   build/pre-built/aarch64-apple-darwin/            (runtime payload)
#   build/pre-built/aarch64-apple-darwin.tgz         (tarball; push via runtime-push.sh arm64)

set -uo pipefail

export CARBONYL_ROOT=$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")
cd "$CARBONYL_ROOT"
# shellcheck disable=SC1091
source scripts/env.sh
set +e   # we manage failures explicitly below

ozone="headless"
jobs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ozone) ozone="$2"; shift 2 ;;
    --ozone=*) ozone="${1#--ozone=}"; shift ;;
    -j) jobs="$2"; shift 2 ;;
    -j*) jobs="${1#-j}"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ "$OSTYPE" != darwin* ]]; then
  echo "ERROR: build-macos.sh must run on macOS (got $OSTYPE)" >&2
  exit 2
fi
ARCH="$(uname -m)"   # arm64 on Apple Silicon
TRIPLE="$(scripts/platform-triple.sh "$ARCH")"   # aarch64-apple-darwin
OUT="out/Default-${ozone}-mac"

# ── 1. CLT toolchain shims (no full Xcode) ──────────────────────────────────
TC="$CARBONYL_ROOT/chromium/.macos-toolchain"
mkdir -p "$TC"

# xcodebuild shim: Chromium's sdk_info.py only needs `xcodebuild -version`.
cat > "$TC/xcodebuild" <<'SH'
#!/bin/bash
case "${1:-}" in
  -version) echo "Xcode 26.2"; echo "Build version 25C58" ;;
  -showsdks) v="$(/usr/bin/xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo 26.4)"
             echo "macOS SDKs:"; echo "        macOS ${v}                       -sdk macosx${v}" ;;
  *) exit 0 ;;
esac
SH
chmod +x "$TC/xcodebuild"

# python3 >= 3.10: macOS system python3 is 3.9 (no PEP 604), and env.sh appends
# depot_tools so the system python wins. Pin depot_tools' bootstrapped python.
BOOTPY="$(ls -d "$CARBONYL_ROOT"/chromium/depot_tools/bootstrap-2@*/python3/bin/python3 2>/dev/null | head -1)"
if [ -z "$BOOTPY" ] || ! "$BOOTPY" -c 'x: int|str=1' >/dev/null 2>&1; then
  echo "ERROR: depot_tools bootstrap python3 (>=3.10) not found; run scripts/gclient.sh sync" >&2
  exit 1
fi
ln -sf "$BOOTPY" "$TC/python3"
ln -sf "$BOOTPY" "$TC/python"
export PATH="$TC:$PATH"
echo "[build-macos] python3 -> $(python3 --version 2>&1); xcodebuild -> shim"

# clang opens many SDK framework headers; macOS default soft FD limit (256) is
# far too low. Raise to the per-process cap.
ulimit -n 61440 2>/dev/null || true
echo "[build-macos] ulimit -n=$(ulimit -n)"

# ── 2. libcarbonyl (Rust) ───────────────────────────────────────────────────
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.13}"
echo "[build-macos] cargo build libcarbonyl ($TRIPLE)"
cargo build --target "$TRIPLE" --release || { echo "ERROR: cargo build failed" >&2; exit 1; }

# ── 3. gn gen with the macOS arg set ────────────────────────────────────────
mkdir -p "$CHROMIUM_SRC/$OUT"
cp "$CARBONYL_ROOT/src/browser/args.macos.gn" "$CHROMIUM_SRC/$OUT/args.gn"
# stage libcarbonyl so the build can link against it (@executable_path)
DYLIB="$CARBONYL_ROOT/build/$TRIPLE/release/libcarbonyl.dylib"
install_name_tool -id @executable_path/libcarbonyl.dylib "$DYLIB" 2>/dev/null
cp "$DYLIB" "$CHROMIUM_SRC/$OUT/"
( cd "$CHROMIUM_SRC" && gn gen "$OUT" ) || { echo "ERROR: gn gen failed" >&2; exit 1; }

# ── 4. ninja headless_shell ─────────────────────────────────────────────────
: "${jobs:=$(( $(sysctl -n hw.ncpu) > 10 ? 10 : $(sysctl -n hw.ncpu) - 2 ))}"
[ "$jobs" -lt 1 ] 2>/dev/null && jobs=4
echo "[build-macos] ninja headless:headless_shell -j$jobs"
( cd "$CHROMIUM_SRC" && ninja -C "$OUT" -j "$jobs" headless:headless_shell ) \
  || { echo "ERROR: ninja build failed" >&2; exit 1; }

# ── 5. Package (mac payload: static ANGLE -> swiftshader, no libEGL/GLESv2) ──
DEST="$CARBONYL_ROOT/build/pre-built/$TRIPLE"
SRC="$CHROMIUM_SRC/$OUT"
rm -rf "$DEST"; mkdir -p "$DEST"
cp "$SRC/headless_shell" "$DEST/carbonyl"
cp "$SRC/icudtl.dat" "$DEST/"
cp "$SRC/libcarbonyl.dylib" "$DEST/"
cp "$SRC"/v8_context_snapshot*.bin "$DEST/"
[ -f "$SRC/libvk_swiftshader.dylib" ] && cp "$SRC/libvk_swiftshader.dylib" "$DEST/"
( cd "$DEST" && strip carbonyl >/dev/null 2>&1; strip -x ./*.dylib >/dev/null 2>&1 )
( cd "$CARBONYL_ROOT/build/pre-built" && tar czf "$TRIPLE.tgz" "$TRIPLE" )

echo "[build-macos] DONE"
echo "  payload : $DEST"
echo "  tarball : $CARBONYL_ROOT/build/pre-built/$TRIPLE.tgz ($(du -h "$CARBONYL_ROOT/build/pre-built/$TRIPLE.tgz" | cut -f1))"
echo "  smoke   : ( cd \"$DEST\" && ./carbonyl --version )"
echo "  publish : CARBONYL_OZONE_TAG=$ozone GITEA_TOKEN=<token> bash scripts/runtime-push.sh $ARCH"
