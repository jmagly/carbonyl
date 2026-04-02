#!/usr/bin/env bash
# build-local.sh — Build a local Carbonyl binary without a full Chromium build.
#
# Strategy:
#   1. Download the pre-built Chromium runtime for the current platform
#      (headless_shell + EGL/GLESv2/Vulkan/V8/ICU) from carbonyl.fathy.fr
#   2. Build libcarbonyl.so from Rust source (takes ~10s)
#   3. Swap the fresh libcarbonyl.so into the pre-built runtime directory
#
# The Chromium runtime is keyed on a hash of:
#   - chromium/.gclient  (Chromium version)
#   - all patch files    (Chromium/Skia/WebRTC patches)
#   - bridge C++ files   (FFI surface)
#
# When any of those change (e.g. Chromium bump, patch update), a new runtime
# hash is computed and the pre-built binary must be rebuilt via Docker:
#   scripts/docker-build.sh
#
# Usage:
#   scripts/build-local.sh          # current platform
#   scripts/build-local.sh "" arm64 # cross-compile lib, pull arm64 runtime

set -euo pipefail

export CARBONYL_ROOT
CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")"

cd "$CARBONYL_ROOT"
source scripts/env.sh

cpu="${2:-}"
triple="$(scripts/platform-triple.sh "$cpu")"
dest="build/pre-built/$triple"

echo "==> Platform: $triple"

# ── 1. Pull pre-built Chromium runtime ────────────────────────────────────────
if [ -f "$dest/carbonyl" ]; then
    echo "==> Pre-built runtime already present at $dest, skipping download"
    echo "    (delete $dest to force re-download)"
else
    echo "==> Downloading pre-built Chromium runtime..."
    scripts/runtime-pull.sh "$cpu"
fi

# ── 2. Build libcarbonyl (Rust) ───────────────────────────────────────────────
echo "==> Building libcarbonyl (Rust)..."
source "$HOME/.cargo/env" 2>/dev/null || true

cargo build --target "$triple" --release

lib_ext="so"
if [ -f "build/$triple/release/libcarbonyl.dylib" ]; then
    lib_ext="dylib"
fi

# ── 3. Swap in fresh library ──────────────────────────────────────────────────
echo "==> Installing libcarbonyl.$lib_ext into $dest"
cp "build/$triple/release/libcarbonyl.$lib_ext" "$dest/libcarbonyl.$lib_ext"

echo ""
echo "==> Build complete: $dest/carbonyl"
echo "    Run: LD_LIBRARY_PATH=$dest $dest/carbonyl https://duckduckgo.com"
echo "    Or:  .venv/bin/python automation/browser.py search 'your query'"
