#!/usr/bin/env bash
# run.sh — issue #178/#217 non-ASCII input verification (see verify.py / README).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
: "${CARBONYL_BIN:=$ROOT/build/pre-built/x86_64-unknown-linux-gnu/carbonyl}"
[[ -x "$CARBONYL_BIN" ]] || { echo "CARBONYL_BIN not executable: $CARBONYL_BIN" >&2; exit 2; }
echo "[issue-178] runtime: $CARBONYL_BIN"
CARBONYL_BIN="$CARBONYL_BIN" python3 "$HERE/verify.py" "$@"
