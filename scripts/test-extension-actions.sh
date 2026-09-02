#!/usr/bin/env bash

set -euo pipefail

: "${CARBONYL_BIN:?set CARBONYL_BIN to the checksummed Carbonyl artifact}"
: "${CARBONYL_UI_TEST_GUEST:?set to 1 only in the disposable UI guest}"
[ "$CARBONYL_UI_TEST_GUEST" = 1 ] || exit 2
[ "${DISPLAY:-}" = :99 ] || { echo "guest-local Xorg :99 is required" >&2; exit 2; }
[ -z "${WAYLAND_DISPLAY:-}" ] || { echo "Wayland access is forbidden" >&2; exit 2; }

for command_name in python3 script xdotool; do
  command -v "$command_name" >/dev/null
done
python3 -c 'from PIL import Image' >/dev/null 2>&1 || {
  echo "Python Pillow is required" >&2
  exit 2
}
if command -v scrot >/dev/null 2>&1; then
  capture_frame() { scrot --overwrite "$1"; }
elif command -v import >/dev/null 2>&1; then
  capture_frame() { import -window root "$1"; }
else
  echo "scrot or ImageMagick import is required" >&2
  exit 2
fi

CARBONYL_ROOT="$(cd "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/carbonyl-extension-actions.XXXXXX)"
SERVER_PID=
CARBONYL_PID=

cleanup() {
  [ -z "$CARBONYL_PID" ] || kill -TERM "$CARBONYL_PID" 2>/dev/null || true
  [ -z "$CARBONYL_PID" ] || wait "$CARBONYL_PID" 2>/dev/null || true
  [ -z "$SERVER_PID" ] || kill -TERM "$SERVER_PID" 2>/dev/null || true
  [ -z "$SERVER_PID" ] || wait "$SERVER_PID" 2>/dev/null || true
  [ -n "${KEEP_WORK_DIR:-}" ] || rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

cp -a -- "$CARBONYL_ROOT/tests/fixtures/extensions/mv3-runtime" \
  "$TEST_ROOT/extension"
EXTENSION_PATH="$(realpath -- "$TEST_ROOT/extension")"

python3 - "$TEST_ROOT/port" "$CARBONYL_ROOT/tests/fixtures/extensions" <<'PY' &
import http.server
import pathlib
import socketserver
import sys

port_file = pathlib.Path(sys.argv[1])
root = sys.argv[2]
handler = lambda *args, **kwargs: http.server.SimpleHTTPRequestHandler(
    *args, directory=root, **kwargs
)
with socketserver.TCPServer(("127.0.0.1", 0), handler) as server:
    port_file.write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
SERVER_PID=$!
for _ in $(seq 1 50); do [ -s "$TEST_ROOT/port" ] && break; sleep 0.1; done
[ -s "$TEST_ROOT/port" ]
PORT="$(<"$TEST_ROOT/port")"

wait_for_color() {
  local path=$1 red=$2 green=$3 blue=$4 label=$5
  for _ in $(seq 1 100); do
    capture_frame "$path"
    if python3 - "$path" "$red" "$green" "$blue" <<'PY'
import sys
from PIL import Image

path, red, green, blue = sys.argv[1:]
target = (int(red), int(green), int(blue))
image = Image.open(path).convert("RGB")
count = sum(
    1 for color in image.getdata()
    if all(abs(actual - expected) <= 3
           for actual, expected in zip(color, target))
)
raise SystemExit(0 if count >= 1000 else 1)
PY
    then
      return 0
    fi
    sleep 0.1
  done
  echo "$label pixels did not appear" >&2
  return 1
}

focus_window() {
  local window_id=$1 label=$2
  for _ in $(seq 1 100); do
    if xdotool windowfocus --sync "$window_id" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  echo "$label window did not accept X11 focus" >&2
  return 1
}

command=(
  "$CARBONYL_BIN"
  --debug
  --ozone-platform=x11
  --disable-gpu
  --carbonyl-operator-window
  --carbonyl-extension-management=restart
  --carbonyl-extension-list
  "--load-extension=$EXTENSION_PATH"
  "--disable-extensions-except=$EXTENSION_PATH"
  "--user-data-dir=$TEST_ROOT/profile"
  --viewport=1000x700
  --v=1
  "http://127.0.0.1:$PORT/runtime-page.html"
)
printf -v quoted '%q ' "${command[@]}"
COLORTERM=truecolor script -q -f -c "$quoted" "$TEST_ROOT/terminal.log" \
  </dev/null >/dev/null &
CARBONYL_PID=$!

WINDOW_ID=
for _ in $(seq 1 150); do
  WINDOW_ID="$(xdotool search --class '^carbonyl$' 2>/dev/null | head -1 || true)"
  [ -z "$WINDOW_ID" ] || break
  sleep 0.1
done
[ -n "$WINDOW_ID" ] || { echo "operator window not found" >&2; exit 1; }
focus_window "$WINDOW_ID" "operator"

for _ in $(seq 1 100); do
  rg -q 'CARBONYL_EXTENSION_ACTION_STATE [a-p]{32}:1:1:1;' \
    "$TEST_ROOT/terminal.log" && break
  sleep 0.1
done
rg -q 'CARBONYL_EXTENSION_ACTION_STATE [a-p]{32}:1:1:1;' \
  "$TEST_ROOT/terminal.log" || {
    echo "action title/badge state did not become operator-visible" >&2
    exit 1
  }

# Reverse traversal from the page enters Options, then the action button. Both
# are native focus-chain controls and must open same-profile constrained views.
xdotool key shift+Tab Return
for _ in $(seq 1 100); do
  grep -q 'CARBONYL_EXTENSION_SURFACE opened .* kind=options' \
    "$TEST_ROOT/terminal.log" && break
  sleep 0.1
done
grep -q 'CARBONYL_EXTENSION_SURFACE opened .* kind=options' \
  "$TEST_ROOT/terminal.log"
OPTIONS_WINDOW="$(xdotool search --class '^carbonyl-extension$' 2>/dev/null | head -1 || true)"
[ -n "$OPTIONS_WINDOW" ] || { echo "options window not found" >&2; exit 1; }
xdotool windowsize --sync "$OPTIONS_WINDOW" 520 420
wait_for_color "$TEST_ROOT/options.png" 32 96 160 "options surface"
focus_window "$OPTIONS_WINDOW" "options"
xdotool key shift+Tab Return
for _ in $(seq 1 100); do
  xdotool search --class '^carbonyl-extension$' >/dev/null 2>&1 || break
  sleep 0.1
done
xdotool search --class '^carbonyl-extension$' >/dev/null 2>&1 && {
  echo "options close control did not close its surface" >&2
  exit 1
}

focus_window "$WINDOW_ID" "operator"
xdotool key shift+Tab Return
for _ in $(seq 1 100); do
  grep -q 'CARBONYL_EXTENSION_SURFACE opened .* kind=popup' \
    "$TEST_ROOT/terminal.log" && break
  sleep 0.1
done
grep -q 'CARBONYL_EXTENSION_SURFACE opened .* kind=popup' \
  "$TEST_ROOT/terminal.log"
POPUP_WINDOW="$(xdotool search --class '^carbonyl-extension$' 2>/dev/null | head -1 || true)"
[ -n "$POPUP_WINDOW" ] || { echo "popup window not found" >&2; exit 1; }
focus_window "$POPUP_WINDOW" "popup"
wait_for_color "$TEST_ROOT/popup.png" 160 64 32 "popup surface"
xdotool key Tab Return
wait_for_color "$TEST_ROOT/popup-clicked.png" 32 160 80 "popup action"

grep -q 'CARBONYL_EXTENSION_STATUS state=loaded' "$TEST_ROOT/terminal.log"
grep -q 'data-carbonyl-extension-content="loaded"' "$TEST_ROOT/terminal.log"
focus_window "$POPUP_WINDOW" "popup"
xdotool key shift+Tab Return
for _ in $(seq 1 100); do
  xdotool search --class '^carbonyl-extension$' >/dev/null 2>&1 || break
  sleep 0.1
done
xdotool search --class '^carbonyl-extension$' >/dev/null 2>&1 && {
  echo "popup close control did not close its surface" >&2
  exit 1
}
focus_window "$WINDOW_ID" "operator"
# From the address field, forward traversal reaches the first restart-only
# management control. The accepted request must not unload the live action.
xdotool key ctrl+l Tab Return
for _ in $(seq 1 100); do
  grep -q 'CARBONYL_EXTENSION_MANAGEMENT id=.* result=restart_required' \
    "$TEST_ROOT/terminal.log" && break
  sleep 0.1
done
grep -q 'CARBONYL_EXTENSION_MANAGEMENT id=.* result=restart_required' \
  "$TEST_ROOT/terminal.log"
grep -q 'CARBONYL_EXTENSION_ACTION_STATE [a-p]\{32\}:1:1:1;' \
  "$TEST_ROOT/terminal.log"
focus_window "$WINDOW_ID" "operator"
xdotool key alt+F4
for _ in $(seq 1 100); do
  kill -0 "$CARBONYL_PID" 2>/dev/null || break
  sleep 0.1
done
kill -0 "$CARBONYL_PID" 2>/dev/null && {
  echo "operator close did not terminate Carbonyl" >&2
  exit 1
}
wait "$CARBONYL_PID"
CARBONYL_PID=
grep -q 'CARBONYL_STORAGE_FLUSH_RESULT result=complete' \
  "$TEST_ROOT/terminal.log"
echo "PASS: extension action, popup, options, focus, resize, and diagnostics"
