#!/usr/bin/env bash
# issue #160 Amazon regional product-page text diagnostic.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"

: "${CARBONYL_BIN:=$ROOT/build/pre-built/x86_64-unknown-linux-gnu/carbonyl}"
export CARBONYL_BIN

if [[ ! -x "$CARBONYL_BIN" ]]; then
  echo "CARBONYL_BIN not found/executable: $CARBONYL_BIN" >&2
  exit 2
fi

triple="$("$ROOT/scripts/platform-triple.sh")"
export LD_LIBRARY_PATH="$ROOT/build/pre-built/$triple${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

echo "[issue-160] runtime: $CARBONYL_BIN"
python3 "$HERE/verify.py" "$@"
