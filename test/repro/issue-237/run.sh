#!/usr/bin/env bash
# run.sh — issue #237 Shift+Tab reverse-focus verification.
#
# Drives Carbonyl in a PTY against fixture.html and confirms that Shift+Tab
# (terminal back-tab, CSI Z) reverses form focus — i.e. the key modifier mask
# now survives the input FFI (#237) and Blink's DefaultTabEventHandler runs
# reverse traversal. Observed GPU-independently via the OSC title sequence
# (see verify.py and README.md).
#
# Requires a runtime built from a tree carrying the #237 changes:
#   - chromium patch 0009 widened `key_press` to (key, modifiers) and sets
#     blink modifiers from the mask;
#   - src/input parser decodes CSI Z to Tab+shift.
# A pre-#237 runtime drops the modifier (or never decodes CSI Z), so Shift+Tab
# does not reverse focus and this harness fails — exactly the regression guard.
#
# Point CARBONYL_BIN at the runtime; defaults to the repo's pre-built runtime.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"

: "${CARBONYL_BIN:=$ROOT/build/pre-built/x86_64-unknown-linux-gnu/carbonyl}"

if [[ ! -x "$CARBONYL_BIN" ]]; then
  echo "CARBONYL_BIN not found/executable: $CARBONYL_BIN" >&2
  echo "Set CARBONYL_BIN to a runtime carrying the #237 changes." >&2
  exit 2
fi

echo "[issue-237] runtime: $CARBONYL_BIN"
CARBONYL_BIN="$CARBONYL_BIN" python3 "$HERE/verify.py" "$@"
