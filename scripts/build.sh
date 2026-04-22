#!/usr/bin/env bash

export CARBONYL_ROOT=$(cd $(dirname -- "$0") && dirname -- "$(pwd)")
export INSTALL_DEPOT_TOOLS="true"

cd "$CARBONYL_ROOT"
source scripts/env.sh

target="$1"
cpu="$2"

if [ ! -z "$target" ]; then
    shift
fi
if [ ! -z "$cpu" ]; then
    shift
fi

triple=$(scripts/platform-triple.sh "$cpu")

if [ -z "$CARBONYL_SKIP_CARGO_BUILD" ]; then
    if [ -z "$MACOSX_DEPLOYMENT_TARGET" ]; then
        export MACOSX_DEPLOYMENT_TARGET=10.13
    fi

    cargo build --target "$triple" --release
fi

if [ -f "build/$triple/release/libcarbonyl.dylib" ]; then
    cp "build/$triple/release/libcarbonyl.dylib" "$CHROMIUM_SRC/out/$target"
    install_name_tool \
        -id @executable_path/libcarbonyl.dylib \
        "build/$triple/release/libcarbonyl.dylib"
else
    cp "build/$triple/release/libcarbonyl.so" "$CHROMIUM_SRC/out/$target"
fi

cd "$CHROMIUM_SRC/out/$target"

# Build headless_shell plus the graphics runtime libs that
# copy-binaries.sh copies into the final carbonyl runtime tarball:
# ANGLE (libEGL.so, libGLESv2.so) and SwiftShader Vulkan
# (libvk_swiftshader.so, libvulkan.so.1). Ninja accepts output-file
# names as targets.
ninja headless:headless_shell \
    libEGL.so libGLESv2.so \
    libvk_swiftshader.so libvulkan.so.1 \
    "$@"
