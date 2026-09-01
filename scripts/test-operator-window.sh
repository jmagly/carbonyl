#!/usr/bin/env bash
# X11 smoke for the explicitly experimental Views/Aura operator host (#285).
# Proves one process produces terminal pixels and native-window pixels, then
# proves XTEST pointer and keyboard events reach the hosted WebContents as
# trusted events. Profile handoff/crash coverage belongs to QA #37.

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

[ -x "$CARBONYL_BIN" ] || { echo "FAIL: carbonyl binary not found at $CARBONYL_BIN"; exit 1; }
: "${DISPLAY:?DISPLAY must point to an X server}"
for command_name in python3 script xdotool; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "FAIL: $command_name not on PATH"; exit 1; }
done
python3 -c 'from PIL import Image' >/dev/null 2>&1 || {
    echo "FAIL: Python Pillow is not installed"; exit 1; }
if command -v scrot >/dev/null 2>&1; then
    # Polling reuses the same path.  scrot otherwise preserves the first frame
    # and writes numbered siblings, causing every readiness check to inspect a
    # stale pre-render screenshot.
    capture_frame() { scrot --overwrite "$1"; }
elif command -v import >/dev/null 2>&1; then
    capture_frame() { import -window root "$1"; }
else
    echo "FAIL: either scrot or ImageMagick import must be on PATH"
    exit 1
fi

FIXTURE="$CARBONYL_ROOT/tests/fixtures/operator-window.html"
[ -f "$FIXTURE" ] || { echo "FAIL: fixture missing: $FIXTURE"; exit 1; }
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/carbonyl-operator-test.XXXXXX")"
TERM_LOG="$WORK_DIR/terminal.log"
FRAME_PNG="$WORK_DIR/operator.png"
CLICK_PNG="$WORK_DIR/operator-click.png"

cleanup() {
    if [ -n "${CARBONYL_PID:-}" ]; then
        kill -TERM "$CARBONYL_PID" 2>/dev/null || true
        wait "$CARBONYL_PID" 2>/dev/null || true
    fi
    if [ -z "${KEEP_WORK_DIR:-}" ]; then
        rm -rf -- "$WORK_DIR"
    fi
}
trap cleanup EXIT

CARBONYL_CMD=(
    "$CARBONYL_BIN"
    --ozone-platform=x11
    --carbonyl-operator-window
    "--user-data-dir=$WORK_DIR/profile"
    --viewport=1280x720
)
if [ "${CARBONYL_TEST_NO_SANDBOX:-0}" = 1 ]; then
    CARBONYL_CMD+=(--no-sandbox)
fi
CARBONYL_CMD+=("file://$FIXTURE")
printf -v CARBONYL_CMD_QUOTED '%q ' "${CARBONYL_CMD[@]}"

COLORTERM=truecolor script -q -c "$CARBONYL_CMD_QUOTED" "$TERM_LOG" &
CARBONYL_PID=$!

WINDOW_ID=""
for _ in $(seq 1 "${WINDOW_ATTEMPTS:-100}"); do
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
    sleep "${WINDOW_INTERVAL:-0.1}"
done
if [ -z "$WINDOW_ID" ]; then
    echo "Visible X11 windows at operator-window discovery failure:"
    while IFS= read -r candidate; do
        name="$(xdotool getwindowname "$candidate" 2>/dev/null || true)"
        class="$(xdotool getwindowclassname "$candidate" 2>/dev/null || true)"
        geometry="$(xdotool getwindowgeometry --shell "$candidate" 2>/dev/null |
            tr '\n' ' ' || true)"
        printf '  id=%s name=%q class=%q %s\n' \
            "$candidate" "$name" "$class" "$geometry"
    done < <(xdotool search --name '.*' 2>/dev/null || true)
    echo "FAIL: Carbonyl operator window not found"
    exit 1
fi

xdotool windowmap --sync "$WINDOW_ID"
xdotool windowraise "$WINDOW_ID"
xdotool windowactivate --sync "$WINDOW_ID" 2>/dev/null ||
    xdotool windowfocus --sync "$WINDOW_ID"

# Do not inject input until the page's initial red button and blue background
# have reached the native window. This avoids turning compositor startup races
# into false input failures.
initial_ready=0
for _ in $(seq 1 "${INITIAL_ATTEMPTS:-50}"); do
    capture_frame "$FRAME_PNG"
    if python3 - "$FRAME_PNG" <<'PY'
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert("RGB")
colors = image.getcolors(maxcolors=image.width * image.height) or []

def count_near(target, tolerance=3):
    return sum(
        count for count, color in colors
        if all(abs(actual - expected) <= tolerance
               for actual, expected in zip(color, target))
    )

raise SystemExit(
    0 if count_near((170, 0, 0)) >= 1000
    and count_near((0, 51, 102)) >= 1000 else 1
)
PY
    then
        initial_ready=1
        break
    fi
    sleep "${INITIAL_INTERVAL:-0.1}"
done
[ "$initial_ready" = 1 ] || {
    echo "FAIL: initial page pixels never reached operator window"; exit 1; }

# This point is inside the rasterized button in the fixed smoke fixture.
xdotool mousemove --sync --window "$WINDOW_ID" 60 20 click 1

click_ready=0
for _ in $(seq 1 "${CLICK_ATTEMPTS:-50}"); do
    capture_frame "$CLICK_PNG"
    if python3 - "$CLICK_PNG" <<'PY'
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert("RGB")
colors = image.getcolors(maxcolors=image.width * image.height) or []
green = sum(
    count for count, color in colors
    if all(abs(actual - expected) <= 3
           for actual, expected in zip(color, (0, 170, 68)))
)
raise SystemExit(0 if green >= 1000 else 1)
PY
    then
        click_ready=1
        break
    fi
    sleep "${CLICK_INTERVAL:-0.1}"
done
[ "$click_ready" = 1 ] || {
    echo "FAIL: trusted pointer visual marker missing"; exit 1; }

xdotool type --window "$WINDOW_ID" --delay 30 'trusted-keyboard'
sleep "${SETTLE_SECONDS:-2}"

capture_frame "$FRAME_PNG"
[ -s "$FRAME_PNG" ] || { echo "FAIL: screenshot is empty"; exit 1; }

python3 - "$FRAME_PNG" <<'PY'
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert("RGB")
colors = image.getcolors(maxcolors=image.width * image.height) or []

def count_near(target, tolerance=3):
    total = 0
    for count, color in colors:
        if all(abs(actual - expected) <= tolerance
               for actual, expected in zip(color, target)):
            total += count
    return total

gold = count_near((102, 85, 0))
print(f"operator pixels: click=verified gold={gold}")
if gold < 500:
    raise SystemExit("trusted keyboard visual marker missing")
PY

quadrants="$(python3 - "$TERM_LOG" <<'PY'
import sys

with open(sys.argv[1], "rb") as stream:
    print(stream.read().count(b"\xe2\x96"))
PY
)"
if [ "$quadrants" -lt "${MIN_QUADRANT_RUNS:-50}" ]; then
    echo "FAIL: terminal compositor produced only $quadrants quadrant glyphs"
    exit 1
fi

echo "PASS: Views/Aura native pixels, trusted pointer/keyboard input, and terminal output"
