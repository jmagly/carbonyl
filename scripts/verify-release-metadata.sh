#!/usr/bin/env bash
# Verify package metadata matches the semantic release version.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/verify-release-metadata.sh <version>

Checks package.json, Cargo.toml, and the carbonyl package entry in Cargo.lock.
The version may be passed with or without a leading "v".
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

[ $# -eq 1 ] || { usage >&2; exit 2; }

version="${1#v}"
[ -n "$version" ] || { usage >&2; exit 2; }

pkg_version="$(node -p "require('./package.json').version")"
cargo_version="$(sed -n '/^\[package\]/,/^\[/s/^version = \"\(.*\)\"/\1/p' Cargo.toml | head -1)"
lock_version="$(awk '
    $0 == "[[package]]" { in_pkg=0 }
    $0 == "name = \"carbonyl\"" { in_pkg=1 }
    in_pkg && /^version = / { gsub(/"/, "", $3); print $3; exit }
' Cargo.lock)"

if [ "$pkg_version" != "$version" ] || [ "$cargo_version" != "$version" ] || [ "$lock_version" != "$version" ]; then
    echo "ERROR: release version metadata mismatch" >&2
    echo "  requested:     $version" >&2
    echo "  package.json:  $pkg_version" >&2
    echo "  Cargo.toml:    $cargo_version" >&2
    echo "  Cargo.lock:    $lock_version" >&2
    exit 1
fi

echo "[release] metadata version assertion passed: $version"
