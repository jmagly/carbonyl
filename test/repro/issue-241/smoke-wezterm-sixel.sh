#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname -- "$0")/../../.." && pwd)"
cd "$ROOT"

BIN="${CARBONYL_BIN:-build/pre-built/x86_64-unknown-linux-gnu/carbonyl}"
LIB_DIR="$(dirname "$BIN")"
OUT_DIR="${OUT_DIR:-.aiwg/measurements/issue-241}"
URL="${1:-file://$ROOT/test/repro/issue-241/fixture.html}"
MODE="${MODE:-sixel}"
CARBONYL_IMAGE_ENV=()
case "$MODE" in
    sixel) CARBONYL_IMAGE_ARGS=(--sixel) ;;
    kitty) CARBONYL_IMAGE_ARGS=(--terminal-image=kitty) ;;
    iterm2) CARBONYL_IMAGE_ARGS=(--terminal-image=iterm2) ;;
    auto-sixel) CARBONYL_IMAGE_ARGS=(--terminal-image=auto) ;;
    auto-kitty)
        CARBONYL_IMAGE_ENV=(KITTY_WINDOW_ID=1)
        CARBONYL_IMAGE_ARGS=(--terminal-image=auto)
        ;;
    auto-iterm2)
        CARBONYL_IMAGE_ENV=(TERM_PROGRAM=iTerm.app)
        CARBONYL_IMAGE_ARGS=(--terminal-image=auto)
        ;;
    *)
        echo "FAIL: unsupported MODE=$MODE (expected sixel, kitty, iterm2, auto-sixel, auto-kitty, or auto-iterm2)" >&2
        exit 2
        ;;
esac

CLASS="carbonyl-issue-241-${MODE}-$RANDOM-$$"
CAPTURE_XWD="$OUT_DIR/wezterm-${MODE}-smoke.xwd"
CAPTURE_PNM="$OUT_DIR/wezterm-${MODE}-smoke.ppm"
CAPTURE_PNG="$OUT_DIR/wezterm-${MODE}-smoke.png"
LOG="$OUT_DIR/wezterm-${MODE}-smoke.log"

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "SKIP: missing required command: $1" >&2
        exit 77
    }
}

require wezterm
require xdotool
require xwd
require xwdtopnm
require pnmtopng
require pnmfile

if [ -z "${DISPLAY:-}" ]; then
    echo "SKIP: DISPLAY is not set" >&2
    exit 77
fi

if [ ! -x "$BIN" ]; then
    echo "SKIP: Carbonyl binary not executable: $BIN" >&2
    exit 77
fi

mkdir -p "$OUT_DIR"
rm -f "$CAPTURE_XWD" "$CAPTURE_PNM" "$CAPTURE_PNG" "$LOG"

WEZTERM_CONFIG_HOME="$(mktemp -d)"
trap 'rm -rf "$WEZTERM_CONFIG_HOME"; [ -n "${WEZTERM_PID:-}" ] && kill "$WEZTERM_PID" 2>/dev/null || true' EXIT

cat >"$WEZTERM_CONFIG_HOME/wezterm.lua" <<'LUA'
local wezterm = require 'wezterm'
return {
  check_for_updates = false,
  enable_wayland = false,
  font_size = 12.0,
  initial_cols = 120,
  initial_rows = 40,
}
LUA

WEZTERM_CONFIG_DIR="$WEZTERM_CONFIG_HOME" \
wezterm start \
    --always-new-process \
    --class "$CLASS" \
    --cwd "$ROOT" \
    -- bash -lc "
        export LD_LIBRARY_PATH='$LIB_DIR'\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
        timeout 8s env ${CARBONYL_IMAGE_ENV[*]} '$BIN' --no-sandbox ${CARBONYL_IMAGE_ARGS[*]} --viewport=640x400 '$URL'
        sleep 2
    " >"$LOG" 2>&1 &
WEZTERM_PID=$!

window_id=""
for _ in $(seq 1 80); do
    window_id="$(xdotool search --class "$CLASS" 2>/dev/null | tail -1 || true)"
    [ -n "$window_id" ] && break
    sleep 0.1
done

if [ -z "$window_id" ]; then
    echo "FAIL: no WezTerm window found for class $CLASS" >&2
    tail -40 "$LOG" >&2 || true
    exit 1
fi

sleep 5
xwd -silent -id "$window_id" -out "$CAPTURE_XWD"
xwdtopnm "$CAPTURE_XWD" >"$CAPTURE_PNM" 2>>"$LOG"
pnmfile "$CAPTURE_PNM" >"$OUT_DIR/wezterm-${MODE}-smoke.pnmfile"
pnmtopng "$CAPTURE_PNM" >"$CAPTURE_PNG"

if [ ! -s "$CAPTURE_PNG" ]; then
    echo "FAIL: empty PNG capture: $CAPTURE_PNG" >&2
    exit 1
fi

printf "PASS: captured WezTerm %s smoke window %s\n" "$MODE" "$window_id"
cat "$OUT_DIR/wezterm-${MODE}-smoke.pnmfile"
printf "capture=%s\n" "$CAPTURE_PNG"
