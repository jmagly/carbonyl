#!/usr/bin/env bash
# runtime-pull.sh — Download a pre-built Chromium runtime from Gitea releases.
#
# The runtime is keyed on a hash of:
#   - chromium/.gclient        (Chromium version)
#   - all patch files          (Chromium/Skia/WebRTC patches)
#   - bridge C++ files         (FFI surface)
#
# The release tag is "runtime-<hash>". The asset is "<triple>.tgz".
#
# Usage:
#   scripts/runtime-pull.sh           # current platform
#   scripts/runtime-pull.sh arm64     # arm64 platform

set -euo pipefail

export CARBONYL_ROOT=$(cd $(dirname -- "$0") && dirname -- $(pwd))

cd "$CARBONYL_ROOT"
source "scripts/env.sh"

echo "Computing Chromium patches sha.."

sha="$(scripts/runtime-hash.sh)"
triple="$(scripts/platform-triple.sh "$@")"

if [ -f "build/pre-built/$triple.tgz" ]; then
    echo "==> Tarball already present at build/pre-built/$triple.tgz, skipping download"
    echo "    (delete it to force re-download)"
else
    GITEA_BASE="${GITEA_BASE:-https://git.integrolabs.net}"
    url="$GITEA_BASE/roctinam/carbonyl/releases/download/runtime-$sha/$triple.tgz"

    echo "Downloading pre-built binaries from $url"

    mkdir -p build/pre-built

    if ! curl --silent --fail --location --output "build/pre-built/$triple.tgz" "$url"; then
        echo ""
        echo "ERROR: Pre-built binaries not available for hash $sha ($triple)"
        echo ""
        echo "This usually means the M135 runtime hasn't been uploaded yet."
        echo "Build it with Docker first, then push:"
        echo ""
        echo "  bash scripts/docker-build.sh Default"
        echo "  bash scripts/copy-binaries.sh Default"
        echo "  GITEA_TOKEN=<token> bash scripts/runtime-push.sh"
        echo ""
        exit 1
    fi
fi

echo "Pre-built binaries available, extracting.."

cd build/pre-built
rm -rf "$triple"
tar -xzf "$triple.tgz"
