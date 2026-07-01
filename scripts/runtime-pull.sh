#!/usr/bin/env bash
# runtime-pull.sh — Download a pre-built Chromium runtime release asset.
#
# The runtime is keyed on a hash of:
#   - chromium/.gclient        (Chromium version)
#   - all patch files          (Chromium/Skia/WebRTC patches)
#   - bridge C++ files         (FFI surface)
#   - Rust sources under src/  (libcarbonyl source; added per #92)
#   - Cargo.{toml,lock}        (Rust dep state)
#   - rust-toolchain.toml      (Rust toolchain pin)
#
# The release tag is "runtime-<hash>" for the headless ozone variant
# and "runtime-<ozone>-<hash>" for any other variant (e.g. x11).
#
# Usage:
#   scripts/runtime-pull.sh                     # current platform, headless
#   scripts/runtime-pull.sh arm64               # arm64, headless
#   scripts/runtime-pull.sh --ozone=x11         # current platform, x11 variant
#   scripts/runtime-pull.sh --ozone x11 amd64   # explicit cpu, x11 variant
#   scripts/runtime-pull.sh --version 0.2.0-alpha.16
#   scripts/runtime-pull.sh --version 0.2.0-alpha.16 --dry-run
#
# CARBONYL_OZONE_TAG env var also works (e.g. for CI). The CLI flag
# wins when both are set.

set -euo pipefail

print_usage() {
    sed -n '2,20p' "$0" | sed 's/^# \?//'
}

# Default ozone variant from env, overridden by --ozone=… below.
ozone="${CARBONYL_OZONE_TAG:-headless}"
release_version="${CARBONYL_RUNTIME_VERSION:-}"
dry_run=false

positional=()
while [ $# -gt 0 ]; do
    case "$1" in
        --ozone=*) ozone="${1#--ozone=}" ;;
        --ozone)
            [ $# -ge 2 ] || { echo "ERROR: --ozone requires a value" >&2; exit 2; }
            ozone="$2"
            shift
            ;;
        --version=*) release_version="${1#--version=}" ;;
        --version)
            [ $# -ge 2 ] || { echo "ERROR: --version requires a value" >&2; exit 2; }
            release_version="$2"
            shift
            ;;
        --dry-run) dry_run=true ;;
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

triple="$(scripts/platform-triple.sh "$@")"

urls=()
checksum_urls=()
version_check=""
target_tgz=""

if [ -n "$release_version" ]; then
    version="${release_version#v}"
    tag="v$version"
    version_check="$version"
    if [ "$ozone" = "headless" ]; then
        asset_name="carbonyl-${version}-${triple}.tgz"
    else
        asset_name="carbonyl-${version}-${ozone}-${triple}.tgz"
    fi
    target_tgz="build/pre-built/$asset_name"

    github_base="${GITHUB_RELEASE_BASE:-https://github.com/jmagly/carbonyl}"
    gitea_base="${GITEA_BASE:-https://git.integrolabs.net}"
    urls+=("$github_base/releases/download/$tag/$asset_name")
    urls+=("$gitea_base/roctinam/carbonyl/releases/download/$tag/$asset_name")
    checksum_urls+=("$github_base/releases/download/$tag/$asset_name.sha256")
    checksum_urls+=("$gitea_base/roctinam/carbonyl/releases/download/$tag/$asset_name.sha256")
else
    echo "Computing Chromium patches sha.."

    sha="$(scripts/runtime-hash.sh)"

    # Tag-shape rule (mirror of runtime-push.sh):
    #   headless  → "runtime-<hash>"        (preserves historical tag)
    #   any other → "runtime-<ozone>-<hash>"
    case "$ozone" in
        headless) tag="runtime-$sha" ;;
        *)        tag="runtime-$ozone-$sha" ;;
    esac
    asset_name="$triple.tgz"
    target_tgz="build/pre-built/$asset_name"
    gitea_base="${GITEA_BASE:-https://git.integrolabs.net}"
    urls+=("$gitea_base/roctinam/carbonyl/releases/download/$tag/$asset_name")
fi

if [ "$dry_run" = true ]; then
    echo "Runtime acquisition plan"
    echo "  triple:       $triple"
    echo "  ozone:        $ozone"
    echo "  tag:          $tag"
    echo "  install path: $CARBONYL_ROOT/build/pre-built/$triple"
    echo "  tarball:      $CARBONYL_ROOT/$target_tgz"
    echo "  urls:"
    printf '    - %s\n' "${urls[@]}"
    if [ "${#checksum_urls[@]}" -gt 0 ]; then
        echo "  checksum urls:"
        printf '    - %s\n' "${checksum_urls[@]}"
    fi
    exit 0
fi

if [ -f "$target_tgz" ]; then
    echo "==> Tarball already present at $target_tgz, skipping download"
    echo "    (delete it to force re-download)"
else
    mkdir -p build/pre-built

    downloaded=false
    for i in "${!urls[@]}"; do
        url="${urls[$i]}"
        echo "Downloading pre-built binaries from $url"
        if curl --silent --fail --location --output "$target_tgz" "$url"; then
            downloaded=true
            if [ "${#checksum_urls[@]}" -gt 0 ]; then
                checksum_url="${checksum_urls[$i]}"
                echo "Downloading checksum from $checksum_url"
                curl --silent --fail --location --output "$target_tgz.sha256" "$checksum_url"
                (
                    cd build/pre-built
                    target_name="$(basename "$target_tgz")"
                    checksum_name="$(basename "$target_tgz.sha256")"
                    expected_name="$(awk '{print $2}' "$checksum_name")"
                    if [ "$expected_name" != "$target_name" ]; then
                        awk -v name="$target_name" '{print $1 "  " name}' "$checksum_name" > "$checksum_name.local"
                        sha256sum -c "$checksum_name.local"
                        rm -f "$checksum_name.local"
                    else
                        sha256sum -c "$checksum_name"
                    fi
                )
            fi
            break
        fi
    done

    if [ "$downloaded" != true ]; then
        echo ""
        echo "ERROR: Pre-built binaries not available for $tag ($triple)"
        echo "Attempted URLs:"
        printf '  %s\n' "${urls[@]}"
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
tar -xzf "$(basename "$target_tgz")"

if [ -n "$version_check" ] && [ -x "$triple/carbonyl" ]; then
    got="$("./$triple/carbonyl" --version)"
    want="Carbonyl $version_check"
    if [ "$got" != "$want" ]; then
        echo "ERROR: downloaded runtime version mismatch" >&2
        echo "  expected: $want" >&2
        echo "  actual:   $got" >&2
        exit 1
    fi
    echo "Verified runtime version: $got"
fi
