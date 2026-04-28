#!/usr/bin/env bash
# runtime-pull.sh — Download a pre-built Chromium runtime from Gitea releases.
#
# The runtime is keyed on a hash of:
#   - chromium/.gclient        (Chromium version)
#   - all patch files          (Chromium/Skia/WebRTC patches)
#   - bridge C++ files         (FFI surface)
#
# The release tag is "runtime-<hash>" for the headless ozone variant
# and "runtime-<ozone>-<hash>" for any other variant (e.g. x11).
#
# Usage:
#   scripts/runtime-pull.sh                     # current platform, headless
#   scripts/runtime-pull.sh arm64               # arm64, headless
#   scripts/runtime-pull.sh --ozone=x11         # current platform, x11 variant
#   scripts/runtime-pull.sh --ozone x11 amd64   # explicit cpu, x11 variant
#
# CARBONYL_OZONE_TAG env var also works (e.g. for CI). The CLI flag
# wins when both are set.

set -euo pipefail

print_usage() {
    sed -n '2,17p' "$0" | sed 's/^# \?//'
}

# Default ozone variant from env, overridden by --ozone=… below.
ozone="${CARBONYL_OZONE_TAG:-headless}"

positional=()
while [ $# -gt 0 ]; do
    case "$1" in
        --ozone=*) ozone="${1#--ozone=}" ;;
        --ozone)
            [ $# -ge 2 ] || { echo "ERROR: --ozone requires a value" >&2; exit 2; }
            ozone="$2"
            shift
            ;;
        -h|--help) print_usage; exit 0 ;;
        --) shift; while [ $# -gt 0 ]; do positional+=("$1"); shift; done; break ;;
        -*) echo "ERROR: unknown option: $1" >&2; print_usage >&2; exit 2 ;;
        *) positional+=("$1") ;;
    esac
    shift
done
set -- "${positional[@]+"${positional[@]}"}"

export CARBONYL_ROOT=$(cd $(dirname -- "$0") && dirname -- $(pwd))

cd "$CARBONYL_ROOT"
source "scripts/env.sh"

echo "Computing Chromium patches sha.."

sha="$(scripts/runtime-hash.sh)"
triple="$(scripts/platform-triple.sh "$@")"

# Tag-shape rule (mirror of runtime-push.sh):
#   headless  → "runtime-<hash>"        (preserves historical tag)
#   any other → "runtime-<ozone>-<hash>"
case "$ozone" in
    headless) tag="runtime-$sha" ;;
    *)        tag="runtime-$ozone-$sha" ;;
esac

if [ -f "build/pre-built/$triple.tgz" ]; then
    echo "==> Tarball already present at build/pre-built/$triple.tgz, skipping download"
    echo "    (delete it to force re-download)"
else
    GITEA_BASE="${GITEA_BASE:-https://git.integrolabs.net}"
    url="$GITEA_BASE/roctinam/carbonyl/releases/download/$tag/$triple.tgz"

    echo "Downloading pre-built binaries from $url"

    mkdir -p build/pre-built

    if ! curl --silent --fail --location --output "build/pre-built/$triple.tgz" "$url"; then
        echo ""
        echo "ERROR: Pre-built binaries not available for $tag ($triple)"
        echo ""
        echo "This usually means the runtime hasn't been built/published yet"
        echo "for this ozone variant. Trigger build-runtime.yml with the"
        echo "matching ozone_platform input, or build locally:"
        echo ""
        echo "  bash scripts/docker-build.sh Default"
        echo "  bash scripts/copy-binaries.sh Default"
        echo "  CARBONYL_OZONE_TAG=$ozone GITEA_TOKEN=<token> bash scripts/runtime-push.sh"
        echo ""
        exit 1
    fi
fi

echo "Pre-built binaries available, extracting.."

cd build/pre-built
rm -rf "$triple"
tar -xzf "$triple.tgz"
