#!/usr/bin/env bash
# Verify a versioned Carbonyl runtime tarball reports the release version.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/verify-release-asset-version.sh <asset.tgz> <version>

Extracts the tarball, finds the contained carbonyl binary, runs
`carbonyl --version`, and requires `Carbonyl <version>`.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

[ $# -eq 2 ] || { usage >&2; exit 2; }

asset="$1"
version="${2#v}"
expected="Carbonyl $version"

[ -f "$asset" ] || { echo "ERROR: asset not found: $asset" >&2; exit 1; }

work="$(mktemp -d)"
cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT

tar -xzf "$asset" -C "$work"
bin="$(find "$work" -mindepth 2 -maxdepth 2 -type f -name carbonyl -perm -111 | head -1)"
[ -n "$bin" ] || { echo "ERROR: executable carbonyl binary not found in $asset" >&2; exit 1; }

actual="$("$bin" --version)"
if [ "$actual" != "$expected" ]; then
    echo "ERROR: $asset reports the wrong Carbonyl version" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
fi

echo "[release] version assertion passed: $(basename "$asset") -> $actual"
