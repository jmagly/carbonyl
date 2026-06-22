#!/usr/bin/env bash
# run.sh — issue #199 right-click verification (see verify.py / README.md).
# Requires a runtime carrying the mouse-button FFI (post Stage-2a). Point
# CARBONYL_BIN at it; defaults to the repo's pre-built runtime.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
: "${CARBONYL_BIN:=$ROOT/build/pre-built/x86_64-unknown-linux-gnu/carbonyl}"
if [[ ! -x "$CARBONYL_BIN" ]]; then
  echo "CARBONYL_BIN not found/executable: $CARBONYL_BIN" >&2; exit 2
fi
echo "[issue-199] runtime: $CARBONYL_BIN"
CARBONYL_BIN="$CARBONYL_BIN" python3 "$HERE/verify.py" "$@"
