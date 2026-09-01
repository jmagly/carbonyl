#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${SCRIPT_DIR}/resolve-ninja-jobs.sh"

expect_value() {
    expected="$1"
    shift
    actual="$($RESOLVER "$@" 2>/dev/null)"
    [[ "$actual" == "$expected" ]] || {
        echo "expected ${expected}, got ${actual}: $*" >&2
        exit 1
    }
}

expect_failure() {
    if "$RESOLVER" "$@" >/dev/null 2>&1; then
        echo "expected failure: $*" >&2
        exit 1
    fi
}

expect_value 4 '' 64 4
expect_value 3 '' 6 4
expect_value 1 '' 1 4
expect_value 2 2 64 4
expect_value 4 64 64 4
expect_failure 0 64 4
expect_failure invalid 64 4
expect_failure 2 0 4
expect_failure 2 64 0

echo "PASS: bounded Ninja parallelism contract"
