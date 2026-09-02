#!/usr/bin/env bash
# Native browser-controls acceptance for the explicit X11 operator mode (#288).
# Run only in the disposable Ubuntu 26.04 VM with guest-local Xorg.

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")"
cd "$CARBONYL_ROOT"

if [ -z "${CARBONYL_BIN:-}" ]; then
    if command -v carbonyl >/dev/null 2>&1; then
        CARBONYL_BIN="$(command -v carbonyl)"
    else
        triple="$(scripts/platform-triple.sh)"
        CARBONYL_BIN="build/pre-built/$triple/carbonyl"
        export LD_LIBRARY_PATH="build/pre-built/$triple${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
fi

[ -x "$CARBONYL_BIN" ] || {
    echo "FAIL: carbonyl binary not found at $CARBONYL_BIN"; exit 1; }
: "${CARBONYL_UI_TEST_GUEST:?set CARBONYL_UI_TEST_GUEST=1 only inside the disposable UI-test VM}"
[ "$CARBONYL_UI_TEST_GUEST" = 1 ] || {
    echo "FAIL: native UI acceptance is restricted to the disposable VM"; exit 1; }
: "${DISPLAY:?DISPLAY must point to guest-local Xorg}"
case "$DISPLAY" in
    :99|:99.0) ;;
    *) echo "FAIL: DISPLAY must be the guest-local Xorg display :99"; exit 1 ;;
esac
for command_name in python3 script xclip xdotool; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "FAIL: $command_name not on PATH"; exit 1; }
done
python3 -c 'from PIL import Image' >/dev/null 2>&1 || {
    echo "FAIL: Python Pillow is not installed"; exit 1; }

if command -v scrot >/dev/null 2>&1; then
    capture_frame() { scrot --overwrite "$1"; }
elif command -v import >/dev/null 2>&1; then
    capture_frame() { import -window root "$1"; }
else
    echo "FAIL: either scrot or ImageMagick import must be on PATH"
    exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/carbonyl-controls-test.XXXXXX")"
SERVER_LOG="$WORK_DIR/server.log"
TERM_LOG="$WORK_DIR/terminal.log"
FRAME_PNG="$WORK_DIR/frame.png"

cleanup() {
    if [ -n "${XCLIP_PID:-}" ]; then
        kill -TERM "$XCLIP_PID" 2>/dev/null || true
        wait "$XCLIP_PID" 2>/dev/null || true
    fi
    if [ -n "${CARBONYL_PID:-}" ]; then
        kill -TERM "$CARBONYL_PID" 2>/dev/null || true
        wait "$CARBONYL_PID" 2>/dev/null || true
    fi
    if [ -n "${SERVER_PID:-}" ]; then
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    if [ -z "${KEEP_WORK_DIR:-}" ]; then
        rm -rf -- "$WORK_DIR"
    fi
}
trap cleanup EXIT

python3 tests/fixtures/operator-controls-server.py >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
PORT=""
for _ in $(seq 1 100); do
    PORT="$(awk '/^PORT / { print $2; exit }' "$SERVER_LOG")"
    [ -n "$PORT" ] && break
    sleep 0.05
done
[ -n "$PORT" ] || { echo "FAIL: fixture server did not start"; exit 1; }
BASE_URL="http://127.0.0.1:$PORT"

CARBONYL_CMD=(
    "$CARBONYL_BIN"
    --ozone-platform=x11
    --carbonyl-operator-window
    --debug
    --v=1
    "--user-data-dir=$WORK_DIR/profile"
    --viewport=1000x700
)
if [ "${CARBONYL_TEST_NO_SANDBOX:-0}" = 1 ]; then
    CARBONYL_CMD+=(--no-sandbox)
fi
CARBONYL_CMD+=("$BASE_URL/one")
printf -v CARBONYL_CMD_QUOTED '%q ' "${CARBONYL_CMD[@]}"
COLORTERM=truecolor script -q -f -c "$CARBONYL_CMD_QUOTED" "$TERM_LOG" \
    </dev/null &
CARBONYL_PID=$!

WINDOW_ID=""
for _ in $(seq 1 150); do
    mapfile -t window_candidates < <(
        {
            xdotool search --name '^Carbonyl(OperatorWindow)?$'
            xdotool search --class '^carbonyl$'
            xdotool search --classname '^Carbonyl$'
        } 2>/dev/null | awk '!seen[$0]++' || true
    )
    for candidate in "${window_candidates[@]}"; do
        if xdotool getwindowgeometry "$candidate" >/dev/null 2>&1; then
            WINDOW_ID="$candidate"
            break
        fi
    done
    [ -n "$WINDOW_ID" ] && break
    sleep 0.1
done
[ -n "$WINDOW_ID" ] || { echo "FAIL: operator window not found"; exit 1; }
echo "Operator window id: $WINDOW_ID"
xdotool getwindowgeometry --shell "$WINDOW_ID" \
    | sed 's/^/Operator window /'
xdotool windowmap --sync "$WINDOW_ID"
xdotool windowraise "$WINDOW_ID"
xdotool windowactivate --sync "$WINDOW_ID" 2>/dev/null ||
    xdotool windowfocus --sync "$WINDOW_ID"

color_ready() {
    local red=$1 green=$2 blue=$3 minimum=${4:-500}
    python3 - "$FRAME_PNG" "$red" "$green" "$blue" "$minimum" <<'PY'
import sys
from PIL import Image

path, red, green, blue, minimum = sys.argv[1:]
target = (int(red), int(green), int(blue))
image = Image.open(path).convert("RGB")
count = sum(
    1 for color in image.getdata()
    if all(abs(actual - expected) <= 3
           for actual, expected in zip(color, target))
)
raise SystemExit(0 if count >= int(minimum) else 1)
PY
}

wait_for_color() {
    local red=$1 green=$2 blue=$3 label=$4
    for _ in $(seq 1 100); do
        capture_frame "$FRAME_PNG"
        if color_ready "$red" "$green" "$blue"; then return 0; fi
        sleep 0.1
    done
    echo "FAIL: $label pixels did not appear"
    # Close through the native lifecycle before returning failure. Besides
    # exercising the browser-owned shutdown path, this lets Carbonyl's outer
    # terminal wrapper forward the inner process diagnostics into TERM_LOG.
    xdotool key --window "$WINDOW_ID" alt+F4 2>/dev/null || true
    for _ in $(seq 1 50); do
        ! kill -0 "$CARBONYL_PID" 2>/dev/null && break
        sleep 0.1
    done
    return 1
}

load_stop_count() {
    # `script` records terminal painting and diagnostics in the same stream, so
    # multiple state records may share one physical line. Count matched records,
    # not lines, or a fast navigation can be invisible to the synchronization.
    grep -aoE 'CARBONYL_OPERATOR_CONTROLS back=[01] forward=[01] loading=0' \
        "$TERM_LOG" | wc -l || true
}

wait_for_load_stop_after() {
    local before=$1 label=$2 after=$1
    for _ in $(seq 1 100); do
        after="$(load_stop_count)"
        if [ "$after" -gt "$before" ]; then return 0; fi
        sleep 0.1
    done
    echo "FAIL: $label did not reach browser load-stop state"
    return 1
}

wait_for_color 17 204 68 "page one"
grep -q "security=Local - $BASE_URL" "$TERM_LOG" || {
    echo "FAIL: trustworthy local-origin state missing"; exit 1; }

# Address submission and redirect synchronization.
redirect_stopped_before="$(load_stop_count)"
xdotool key ctrl+l
xdotool type --delay 10 "$BASE_URL/redirect"
xdotool key Return
wait_for_color 34 170 238 "redirect destination"
grep -q '^GET /redirect$' "$SERVER_LOG" || {
    echo "FAIL: address submission did not reach redirect fixture"; exit 1; }
grep -q '^GET /two$' "$SERVER_LOG" || {
    echo "FAIL: redirect destination was not committed"; exit 1; }
wait_for_load_stop_after "$redirect_stopped_before" "redirect destination"

# Selection/copy is native Textfield behavior and must expose the synchronized
# committed URL, not the pre-redirect input.
xdotool mousemove --sync --window "$WINDOW_ID" 500 20 click 1
xdotool mousemove --sync --window "$WINDOW_ID" 990 20
xdotool mousedown 1
xdotool mousemove --sync --window "$WINDOW_ID" 240 20
xdotool mouseup 1
sleep 0.1
capture_frame "$WORK_DIR/clipboard-focus.png"
copied_address=""
for _ in $(seq 1 50); do
    # Reissue copy while native pointer focus settles instead of polling an
    # empty clipboard produced by a Ctrl+C in the same event turn.
    sleep 0.05
    xdotool key ctrl+c
    copied_address="$(xclip -selection clipboard -o 2>/dev/null || true)"
    [ "$copied_address" = "$BASE_URL/two" ] && break
done
[ "$copied_address" = "$BASE_URL/two" ] || {
    printf 'FAIL: copied address is not the committed redirect destination (got %q)\n' \
        "$copied_address"
    exit 1
}
xdotool key Escape

# Stable DIP geometry makes the browser-owned pointer targets deterministic:
# Back center=(38,20), Forward center=(114,20) in the widget client.
pointer_back_stopped_before="$(load_stop_count)"
xdotool mousemove --sync --window "$WINDOW_ID" 38 20 click 1
wait_for_color 17 204 68 "pointer Back"
wait_for_load_stop_after "$pointer_back_stopped_before" "pointer Back"
pointer_forward_stopped_before="$(load_stop_count)"
xdotool mousemove --sync --window "$WINDOW_ID" 114 20 click 1
wait_for_color 34 170 238 "pointer Forward"
wait_for_load_stop_after "$pointer_forward_stopped_before" "pointer Forward"

# Keyboard history controls must work and must not leak to page JavaScript.
keyboard_back_stopped_before="$(load_stop_count)"
xdotool key alt+Left
wait_for_color 17 204 68 "keyboard Back"
wait_for_load_stop_after "$keyboard_back_stopped_before" "keyboard Back"
keyboard_forward_stopped_before="$(load_stop_count)"
xdotool key alt+Right
wait_for_color 34 170 238 "keyboard Forward"
wait_for_load_stop_after "$keyboard_forward_stopped_before" "keyboard Forward"

two_requests_before="$(grep -c '^GET /two$' "$SERVER_LOG" || true)"
reload_stopped_before="$(load_stop_count)"
xdotool key ctrl+r
for _ in $(seq 1 100); do
    two_requests_after="$(grep -c '^GET /two$' "$SERVER_LOG" || true)"
    [ "$two_requests_after" -gt "$two_requests_before" ] && break
    sleep 0.1
done
[ "$two_requests_after" -gt "$two_requests_before" ] || {
    echo "FAIL: Reload did not issue a new request"; exit 1; }
wait_for_load_stop_after "$reload_stopped_before" "Reload"

# Clipboard input exercises native Unicode editing without xdotool's ASCII-only
# type command. URL fixup must encode the path and retain browser ownership of
# submission.
UNICODE_URL="$BASE_URL/✓"
# Quiet mode remains in the foreground, unlike xclip's default/silent mode,
# which forks a clipboard owner that can outlive the test and retain an
# orchestrator/tee file descriptor after the test has passed.
printf '%s' "$UNICODE_URL" | xclip -selection clipboard -quiet &
XCLIP_PID=$!
unicode_stopped_before="$(load_stop_count)"
xdotool key ctrl+l
xdotool key ctrl+v
xdotool key Return
wait_for_color 17 204 68 "Unicode pasted address"
for _ in $(seq 1 100); do
    grep -q '^GET /%E2%9C%93$' "$SERVER_LOG" && break
    sleep 0.1
done
grep -q '^GET /%E2%9C%93$' "$SERVER_LOG" || {
    echo "FAIL: Unicode address was not encoded and submitted"; exit 1; }
wait_for_load_stop_after "$unicode_stopped_before" "Unicode address"
kill -TERM "$XCLIP_PID" 2>/dev/null || true
wait "$XCLIP_PID" 2>/dev/null || true
XCLIP_PID=""
unicode_back_stopped_before="$(load_stop_count)"
xdotool key alt+Left
wait_for_color 34 170 238 "return from Unicode address"
wait_for_load_stop_after "$unicode_back_stopped_before" "return from Unicode address"

# Escape cancels address editing and returns focus to the page's prior input.
xdotool key ctrl+l
xdotool type --delay 10 'unsubmitted operator text'
xdotool key Escape
xdotool type --delay 20 'page-input'
wait_for_color 119 51 170 "address cancel focus return"

# A page must never observe browser shortcut keydowns consumed by Views.
capture_frame "$FRAME_PNG"
if color_ready 170 0 17 100; then
    echo "FAIL: browser shortcut leaked to page input"
    exit 1
fi

# Reload/Stop toggles while a response is intentionally incomplete.
xdotool key ctrl+l
xdotool type --delay 10 "$BASE_URL/slow"
xdotool key Return
for _ in $(seq 1 100); do
    grep -q '^GET /slow$' "$SERVER_LOG" && break
    sleep 0.1
done
grep -q '^GET /slow$' "$SERVER_LOG" || {
    echo "FAIL: slow fixture did not start"; exit 1; }
stopped_before="$(load_stop_count)"
xdotool key ctrl+r
wait_for_load_stop_after "$stopped_before" "Stop"

# Renderer/network failure state remains browser-owned and explicit.
kill -TERM "$SERVER_PID"
wait "$SERVER_PID" || true
SERVER_PID=""
xdotool key ctrl+l
xdotool type --delay 10 "$BASE_URL/offline"
xdotool key Return
error_ready=0
for _ in $(seq 1 150); do
    if grep -q "security=Error page - $BASE_URL" "$TERM_LOG"; then
        error_ready=1
        break
    fi
    sleep 0.1
done
[ "$error_ready" = 1 ] || {
    echo "FAIL: committed error-page security state missing"; exit 1; }

# The key-down closes the window synchronously. Xdotool may receive BadWindow
# while sending the matching key-up, which is expected once the browser-owned
# close lifecycle has already begun.
xdotool key --window "$WINDOW_ID" alt+F4 2>/dev/null || true
for _ in $(seq 1 100); do
    kill -0 "$CARBONYL_PID" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$CARBONYL_PID" 2>/dev/null; then
    echo "FAIL: native close did not terminate Carbonyl"
    exit 1
fi
wait "$CARBONYL_PID"
CARBONYL_PID=""
grep -q 'CARBONYL_STORAGE_FLUSH_RESULT=.*"result":"complete"' "$TERM_LOG" || {
    echo "FAIL: native close did not complete the storage flush"
    exit 1
}
echo "PASS: operator controls, history, redirect, origin, focus, and stop"
