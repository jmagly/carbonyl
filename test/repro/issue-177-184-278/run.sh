#!/usr/bin/env bash
# Local verification for #177/#184/#278. This proves parser and available PTY
# smoke coverage only; it does not replace real SSH/PuTTY validation.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"

cd "$ROOT"

echo "[issue-177-184-278] parser coverage"
cargo test input::parser::tests::sgr_mouse --lib
cargo test input::parser::tests::legacy_mouse --lib

echo "[issue-177-184-278] terminal mouse mode setup"
rg -n "\(1002, true\)|\(1003, true\)|\(1006, true\)" src/input/tty.rs

if [[ -n "${CARBONYL_BIN:-}" ]]; then
  if [[ ! -x "$CARBONYL_BIN" ]]; then
    echo "CARBONYL_BIN is set but not executable: $CARBONYL_BIN" >&2
    exit 2
  fi

  echo "[issue-177-184-278] SSH PTY smoke: local throwaway sshd"
  CARBONYL_BIN="$CARBONYL_BIN" python3 "$HERE/ssh_smoke.py"

  echo "[issue-177-184-278] runtime PTY smoke: right-click mouse path (#199)"
  if CARBONYL_BIN="$CARBONYL_BIN" "$ROOT/test/repro/issue-199/run.sh"; then
    echo "[issue-177-184-278] advisory smoke #199: PASS"
  else
    echo "[issue-177-184-278] advisory smoke #199: FAIL" >&2
  fi

  echo "[issue-177-184-278] runtime PTY smoke: Shift+Tab/modifier input path (#237)"
  if CARBONYL_BIN="$CARBONYL_BIN" "$ROOT/test/repro/issue-237/run.sh"; then
    echo "[issue-177-184-278] advisory smoke #237: PASS"
  else
    echo "[issue-177-184-278] advisory smoke #237: FAIL" >&2
  fi
else
  echo "[issue-177-184-278] CARBONYL_BIN not set; skipping runtime PTY smokes"
fi

echo "[issue-177-184-278] PASS: local deterministic checks completed"
