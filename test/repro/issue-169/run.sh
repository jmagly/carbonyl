#!/usr/bin/env bash
# run.sh — issue #169 TAB-focus verification.
#
# Drives Carbonyl in a PTY against fixture.html and confirms TAB advances form
# focus by observing the OSC title sequence Carbonyl emits (GPU-independent;
# see verify.py and README.md).
#
# Requires a runtime that carries chromium patch 0009 with the
# `0x09 -> VKEY_TAB` case (post-PR #232 / commit 201be82). The verifier sets
# CARBONYL_TAB_FOCUS=1 because Tab focus traversal is now opt-in (#242). Point
# CARBONYL_BIN at it; defaults to the repo's pre-built runtime if unset.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"

: "${CARBONYL_BIN:=$ROOT/build/pre-built/x86_64-unknown-linux-gnu/carbonyl}"

if [[ ! -x "$CARBONYL_BIN" ]]; then
  echo "CARBONYL_BIN not found/executable: $CARBONYL_BIN" >&2
  echo "Set CARBONYL_BIN to a runtime carrying patch 0009 (post-#232)." >&2
  exit 2
fi

echo "[issue-169] runtime: $CARBONYL_BIN"
CARBONYL_BIN="$CARBONYL_BIN" python3 "$HERE/verify.py" "$@"
