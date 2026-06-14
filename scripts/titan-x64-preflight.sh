#!/usr/bin/env bash
# Read-only readiness checks for titan's x86_64 runtime build host.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname -- "$0")/.." && pwd)
HOST_ROOT=${HOST_ROOT:-/srv/carbonyl}
CHROMIUM_SRC=${CHROMIUM_SRC:-"$HOST_ROOT/chromium/src"}
MIN_HOST_FREE_GB=${MIN_HOST_FREE_GB:-200}
MIN_TMP_FREE_GB=${MIN_TMP_FREE_GB:-10}
SKIP_CARGO_CHECK=false
BUILDER_IMAGE=${BUILDER_IMAGE:-}

passes=0
failures=0
warnings=0

usage() {
    cat <<'EOF'
Usage: scripts/titan-x64-preflight.sh [options]

Checks titan's x86_64 runtime-build readiness without mutating the persistent
Chromium checkout or running a Chromium build.

Options:
  --host-root PATH          Persistent Carbonyl root (default: /srv/carbonyl)
  --chromium-src PATH       Chromium src checkout (default: HOST_ROOT/chromium/src)
  --builder-image IMAGE     Builder image to inspect (default: repo pin)
  --min-host-free-gb N      Required free space for HOST_ROOT (default: 200)
  --min-tmp-free-gb N       Required free space for /tmp (default: 10)
  --skip-cargo-check        Skip cargo check; intended only for fast doc testing
  -h, --help                Show this help
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --host-root)
            HOST_ROOT=${2:?--host-root requires a path}
            CHROMIUM_SRC="$HOST_ROOT/chromium/src"
            shift 2
            ;;
        --chromium-src)
            CHROMIUM_SRC=${2:?--chromium-src requires a path}
            shift 2
            ;;
        --builder-image)
            BUILDER_IMAGE=${2:?--builder-image requires an image}
            shift 2
            ;;
        --min-host-free-gb)
            MIN_HOST_FREE_GB=${2:?--min-host-free-gb requires a number}
            shift 2
            ;;
        --min-tmp-free-gb)
            MIN_TMP_FREE_GB=${2:?--min-tmp-free-gb requires a number}
            shift 2
            ;;
        --skip-cargo-check)
            SKIP_CARGO_CHECK=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

pass() {
    passes=$((passes + 1))
    printf '[pass] %s\n' "$1"
}

fail() {
    failures=$((failures + 1))
    printf '[fail] %s\n' "$1"
}

warn() {
    warnings=$((warnings + 1))
    printf '[warn] %s\n' "$1"
}

info() {
    printf '[info] %s\n' "$1"
}

require_command() {
    local command_name="$1"

    if command -v "$command_name" >/dev/null 2>&1; then
        pass "$command_name is on PATH"
    else
        fail "$command_name is not on PATH"
        return 1
    fi
}

read_patch_var() {
    local name="$1"

    sed -nE "s/^${name}=\"([0-9a-f]+)\".*/\\1/p" "$REPO_ROOT/scripts/patches.sh" | head -n 1
}

check_git_commit() {
    local label="$1"
    local repo_path="$2"
    local commit="$3"

    if [ -z "$commit" ]; then
        fail "$label baseline could not be parsed from scripts/patches.sh"
        return
    fi

    if [ ! -d "$repo_path/.git" ]; then
        fail "$label git repo missing at $repo_path"
        return
    fi

    if git -C "$repo_path" cat-file -e "${commit}^{commit}" >/dev/null 2>&1; then
        pass "$label baseline reachable: $commit"
    else
        fail "$label baseline missing: $commit"
    fi
}

check_locks() {
    local label="$1"
    local repo_path="$2"
    local locks

    if [ ! -d "$repo_path/.git" ]; then
        fail "$label git metadata missing at $repo_path/.git"
        return
    fi

    locks=$(find "$repo_path/.git" -maxdepth 1 -type f -name '*.lock' -print 2>/dev/null)
    if [ -z "$locks" ]; then
        pass "$label has no stale .git/*.lock files"
    else
        fail "$label stale git lock files found: $(echo "$locks" | paste -sd ',' -)"
    fi
}

check_disk() {
    local label="$1"
    local path="$2"
    local min_gb="$3"
    local available_kb
    local required_kb
    local available_gb

    if [ ! -e "$path" ]; then
        fail "$label path does not exist: $path"
        return
    fi

    available_kb=$(df -Pk "$path" | awk 'NR == 2 {print $4}')
    required_kb=$((min_gb * 1024 * 1024))
    available_gb=$((available_kb / 1024 / 1024))

    if [ "$available_kb" -ge "$required_kb" ]; then
        pass "$label free space ${available_gb}G >= ${min_gb}G"
    else
        fail "$label free space ${available_gb}G < ${min_gb}G"
    fi
}

echo "Titan x86_64 preflight"
echo "repo_root=$REPO_ROOT"
echo "host_root=$HOST_ROOT"
echo "chromium_src=$CHROMIUM_SRC"

kernel=$(uname -s)
machine=$(uname -m)
if [ "$kernel" = "Linux" ] && { [ "$machine" = "x86_64" ] || [ "$machine" = "amd64" ]; }; then
    pass "host platform is Linux $machine"
else
    fail "host platform must be x86_64 Linux; found $kernel $machine"
fi

if [ -f "$REPO_ROOT/.gitea/builder-image-pin" ]; then
    builder_tag=$(tr -d '[:space:]' < "$REPO_ROOT/.gitea/builder-image-pin")
else
    builder_tag=latest
    warn ".gitea/builder-image-pin missing; using :latest"
fi

if [ -z "$BUILDER_IMAGE" ]; then
    BUILDER_IMAGE="git.integrolabs.net/roctinam/carbonyl-builder:${builder_tag:-latest}"
fi
info "builder_image=$BUILDER_IMAGE"

if require_command docker; then
    if docker info >/dev/null 2>&1; then
        pass "Docker daemon is reachable"
        image_platform=$(docker image inspect "$BUILDER_IMAGE" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null)
        docker_status=$?
        if [ "$docker_status" -ne 0 ]; then
            fail "Docker builder image is not inspectable locally: $BUILDER_IMAGE"
        elif [ "$image_platform" = "linux/amd64" ]; then
            pass "Docker builder image platform is $image_platform"
        else
            fail "Docker builder image platform must be linux/amd64; found $image_platform"
        fi
    else
        fail "Docker daemon is not reachable"
    fi
fi

if [ -d "$CHROMIUM_SRC" ]; then
    pass "Chromium checkout exists at $CHROMIUM_SRC"
else
    fail "Chromium checkout missing at $CHROMIUM_SRC"
fi

platform_triple=$(bash "$REPO_ROOT/scripts/platform-triple.sh" amd64 linux 2>/dev/null)
if [ "$platform_triple" = "x86_64-unknown-linux-gnu" ]; then
    pass "platform triple resolves to $platform_triple"
else
    fail "platform triple should resolve to x86_64-unknown-linux-gnu; got ${platform_triple:-<empty>}"
fi

runtime_hash=$(bash "$REPO_ROOT/scripts/runtime-hash.sh" 2>/dev/null)
if [ -n "$runtime_hash" ]; then
    pass "runtime hash resolves to $runtime_hash"
else
    fail "runtime hash did not resolve"
fi

chromium_upstream=$(read_patch_var chromium_upstream)
skia_upstream=$(read_patch_var skia_upstream)
webrtc_upstream=$(read_patch_var webrtc_upstream)
check_git_commit chromium "$CHROMIUM_SRC" "$chromium_upstream"
check_git_commit skia "$CHROMIUM_SRC/third_party/skia" "$skia_upstream"
check_git_commit webrtc "$CHROMIUM_SRC/third_party/webrtc" "$webrtc_upstream"

check_locks chromium "$CHROMIUM_SRC"
check_locks skia "$CHROMIUM_SRC/third_party/skia"
check_locks webrtc "$CHROMIUM_SRC/third_party/webrtc"

check_disk "$HOST_ROOT" "$HOST_ROOT" "$MIN_HOST_FREE_GB"
check_disk /tmp /tmp "$MIN_TMP_FREE_GB"

if require_command rustc; then
    rustc_version=$(rustc --version 2>/dev/null || true)
    if [ -n "$rustc_version" ]; then
        pass "$rustc_version"
    else
        fail "rustc --version produced no output"
    fi
fi

if require_command cargo; then
    cargo_version=$(cargo --version 2>/dev/null || true)
    if [ -n "$cargo_version" ]; then
        pass "$cargo_version"
    else
        fail "cargo --version produced no output"
    fi

    if [ -f "$REPO_ROOT/rust-toolchain.toml" ]; then
        pass "rust-toolchain.toml is present"
    else
        fail "rust-toolchain.toml is missing"
    fi

    if [ "$SKIP_CARGO_CHECK" = true ]; then
        warn "skipping cargo check by request"
    elif (cd "$REPO_ROOT" && cargo check --target x86_64-unknown-linux-gnu); then
        pass "cargo check --target x86_64-unknown-linux-gnu passed"
    else
        fail "cargo check --target x86_64-unknown-linux-gnu failed"
    fi
fi

echo
echo "Summary: ${passes} passed, ${warnings} warnings, ${failures} failed"

if [ "$failures" -gt 0 ]; then
    exit 1
fi
