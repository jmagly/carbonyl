#!/usr/bin/env bash
# X11 smoke for the experimental Views/Aura host and dedicated shell (#285,
# #286).
# Proves one process produces terminal pixels and native-window pixels, then
# proves resize/focus recovery and XTEST pointer/keyboard events reach the
# hosted WebContents as trusted events. Key and pointer commands intentionally
# omit xdotool --window: targeted events use XSendEvent, while input sent to the
# already-focused window uses XTEST. Profile handoff/crash coverage belongs to
# QA #37; composed IME coverage requires an isolated worker with a real IME.

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")"
cd "$CARBONYL_ROOT"

USE_DEDICATED_OPERATOR_SHELL=0
if [ -n "${CARBONYL_OPERATOR_SHELL_BIN:-}" ]; then
    CARBONYL_BIN="$CARBONYL_OPERATOR_SHELL_BIN"
    USE_DEDICATED_OPERATOR_SHELL=1
elif [ -n "${CARBONYL_BIN:-}" ] &&
    [ -x "$(dirname -- "$CARBONYL_BIN")/carbonyl_operator_shell" ]; then
    CARBONYL_BIN="$(dirname -- "$CARBONYL_BIN")/carbonyl_operator_shell"
    USE_DEDICATED_OPERATOR_SHELL=1
elif [ -z "${CARBONYL_BIN:-}" ]; then
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
for command_name in python3 script xdotool xwininfo; do
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
OPERATOR_PATCH="$CARBONYL_ROOT/chromium/patches/chromium/0037-carbonyl-host-webcontents-in-experimental-operator-.patch"
[ -f "$OPERATOR_PATCH" ] || {
    echo "FAIL: operator patch missing: $OPERATOR_PATCH"; exit 1; }
python3 - "$OPERATOR_PATCH" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
reset = text.find("operator_window_.reset();")
deferred = text.find("browser_->BrowserMainThread()->PostTask(", reset)
shutdown = text.find("browser_.ExtractAsDangling()->Shutdown();", reset)
if reset < 0 or deferred < 0 or shutdown < 0 or not reset < deferred < shutdown:
    raise SystemExit(
        "OperatorWindow teardown must precede deferred HeadlessBrowser shutdown"
    )
operator_mode = text.find("+  const bool use_operator_window =")
real_ime = text.find("+      !use_operator_window) {", operator_mode)
ozone_x11 = text.find('use_operator_window ? "x11" : "headless"', real_ime)
if operator_mode < 0 or real_ime < 0 or ozone_x11 < 0:
    raise SystemExit(
        "Operator browser must omit --headless and select Ozone X11 for IME"
    )
PY
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/carbonyl-operator-test.XXXXXX")"
TERM_LOG="$WORK_DIR/terminal.log"
FRAME_PNG="$WORK_DIR/operator.png"
CLICK_PNG="$WORK_DIR/operator-click.png"
RESIZE_PNG="$WORK_DIR/operator-resize.png"
KEYBOARD_PNG="$WORK_DIR/operator-keyboard.png"
FOCUS_PNG="$WORK_DIR/operator-focus.png"
CONTEXT_PNG="$WORK_DIR/operator-context.png"
WHEEL_PNG="$WORK_DIR/operator-wheel.png"

color_center() {
    python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import sys
from PIL import Image

path, red, green, blue, minimum = sys.argv[1:]
target = (int(red), int(green), int(blue))
minimum = int(minimum)
image = Image.open(path).convert("RGB")
points = [
    (index % image.width, index // image.width)
    for index, color in enumerate(image.getdata())
    if all(abs(actual - expected) <= 3
           for actual, expected in zip(color, target))
]
if len(points) < minimum:
    raise SystemExit(
        f"expected at least {minimum} target pixels, found {len(points)}"
    )
xs, ys = zip(*points)
print((min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2)
PY
}

quadrant_count() {
    python3 - "$TERM_LOG" <<'PY'
import sys

with open(sys.argv[1], "rb") as stream:
    print(stream.read().count(b"\xe2\x96"))
PY
}

release_synthetic_modifiers() {
    local key_name
    for key_name in Alt_L Alt_R F4 Control_L Control_R Shift_L Shift_R; do
        xdotool keyup "$key_name" 2>/dev/null || true
    done
}

cleanup() {
    if [ -n "${CARBONYL_PID:-}" ] && kill -0 "$CARBONYL_PID" 2>/dev/null; then
        if [ -n "${WINDOW_ID:-}" ]; then
            xdotool key --window "$WINDOW_ID" alt+F4 2>/dev/null || true
            release_synthetic_modifiers
            for _ in $(seq 1 50); do
                kill -0 "$CARBONYL_PID" 2>/dev/null || break
                sleep 0.1
            done
        fi
        kill -TERM "$CARBONYL_PID" 2>/dev/null || true
    fi
    [ -z "${CARBONYL_PID:-}" ] || wait "$CARBONYL_PID" 2>/dev/null || true
    if [ -z "${KEEP_WORK_DIR:-}" ]; then
        rm -rf -- "$WORK_DIR"
    fi
}
trap cleanup EXIT

CARBONYL_CMD=(
    "$CARBONYL_BIN"
    --debug
    --ozone-platform=x11
    "--user-data-dir=$WORK_DIR/profile"
    --viewport=1280x720
)
if [ "$USE_DEDICATED_OPERATOR_SHELL" = 0 ]; then
    CARBONYL_CMD+=(--carbonyl-operator-window)
fi
if [ "${CARBONYL_TEST_NO_SANDBOX:-0}" = 1 ]; then
    CARBONYL_CMD+=(--no-sandbox)
fi
CARBONYL_CMD+=("file://$FIXTURE")
printf -v CARBONYL_CMD_QUOTED '%q ' "${CARBONYL_CMD[@]}"

COLORTERM=truecolor script -q -f -c "$CARBONYL_CMD_QUOTED" "$TERM_LOG" \
    </dev/null >/dev/null &
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

# The Widget client bounds are the viewport source of truth. A native WM
# resize must flow through WebView into the existing WebContents, without
# recreating the profile or disrupting terminal output.
quadrants_before_resize="$(quadrant_count)"
xdotool windowsize --sync "$WINDOW_ID" 900 600
resize_ready=0
for _ in $(seq 1 "${RESIZE_ATTEMPTS:-50}"); do
    capture_frame "$RESIZE_PNG"
    if python3 - "$RESIZE_PNG" <<'PY'
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert("RGB")
colors = image.getcolors(maxcolors=image.width * image.height) or []
magenta = sum(
    count for count, color in colors
    if all(abs(actual - expected) <= 3
           for actual, expected in zip(color, (170, 0, 170)))
)
raise SystemExit(0 if magenta >= 500 else 1)
PY
    then
        resize_ready=1
        break
    fi
    sleep "${RESIZE_INTERVAL:-0.1}"
done
[ "$resize_ready" = 1 ] || {
    echo "FAIL: native resize did not reach hosted WebContents"; exit 1; }

# Require fresh terminal output after the resize, rather than accepting glyphs
# that were all emitted during startup.
terminal_progress=0
for _ in $(seq 1 "${TERMINAL_PROGRESS_ATTEMPTS:-50}"); do
    quadrants_after_resize="$(quadrant_count)"
    if [ "$quadrants_after_resize" -ge "$((quadrants_before_resize + ${MIN_POST_RESIZE_QUADRANTS:-10}))" ]; then
        terminal_progress=1
        break
    fi
    sleep "${TERMINAL_PROGRESS_INTERVAL:-0.1}"
done
[ "$terminal_progress" = 1 ] || {
    echo "FAIL: terminal compositor made no measurable post-resize progress"; exit 1; }

# Locate the rendered button in screen coordinates. This keeps the input point
# inside the page client area even when Views or the window manager adds
# non-client decorations.
target_position="$(color_center "$RESIZE_PNG" 170 0 0 1000)" || {
    echo "FAIL: could not locate page button inside decorated window"; exit 1; }
read -r target_x target_y <<<"$target_position"
xdotool mousemove --sync "$target_x" "$target_y" click 1

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

# Keyboard input is a separate assertion from the primary click. The click
# focused the fixture input; omitting --window keeps this on the XTEST path.
xdotool type --delay 30 'trusted-keyboard'
keyboard_ready=0
for _ in $(seq 1 "${KEYBOARD_ATTEMPTS:-50}"); do
    capture_frame "$KEYBOARD_PNG"
    if python3 - "$KEYBOARD_PNG" <<'PY'
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert("RGB")
colors = image.getcolors(maxcolors=image.width * image.height) or []
gold = sum(
    count for count, color in colors
    if all(abs(actual - expected) <= 3
           for actual, expected in zip(color, (102, 85, 0)))
)
raise SystemExit(0 if gold >= 500 else 1)
PY
    then
        keyboard_ready=1
        break
    fi
    sleep "${KEYBOARD_INTERVAL:-0.1}"
done
[ "$keyboard_ready" = 1 ] || {
    echo "FAIL: trusted keyboard visual marker missing"; exit 1; }

# Hide the window only after the input has focus, assert that X11 really
# unmapped it, then restore and type without another page click. The browser-QA
# guest intentionally runs bare Xorg, so there is no window manager to honor a
# _NET_WM_STATE_HIDDEN request. The final marker therefore proves the stored
# page focus was recovered across the actual unmap/map lifecycle.
xdotool windowunmap --sync "$WINDOW_ID"
unmapped=0
for _ in $(seq 1 "${MINIMIZE_ATTEMPTS:-50}"); do
    if xwininfo -id "$WINDOW_ID" 2>/dev/null |
        grep -q 'Map State: IsUnMapped'; then
        unmapped=1
        break
    fi
    sleep "${MINIMIZE_INTERVAL:-0.1}"
done
[ "$unmapped" = 1 ] || {
    echo "FAIL: X11 did not unmap operator window"; exit 1; }

xdotool windowmap --sync "$WINDOW_ID"
xdotool windowactivate --sync "$WINDOW_ID" 2>/dev/null ||
    xdotool windowfocus --sync "$WINDOW_ID"
xdotool type --delay 30 'focus-recovered'

focus_ready=0
for _ in $(seq 1 "${FOCUS_ATTEMPTS:-50}"); do
    capture_frame "$FOCUS_PNG"
    if python3 - "$FOCUS_PNG" <<'PY'
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert("RGB")
colors = image.getcolors(maxcolors=image.width * image.height) or []
purple = sum(
    count for count, color in colors
    if all(abs(actual - expected) <= 3
           for actual, expected in zip(color, (119, 34, 170)))
)
raise SystemExit(0 if purple >= 500 else 1)
PY
    then
        focus_ready=1
        break
    fi
    sleep "${FOCUS_INTERVAL:-0.1}"
done
[ "$focus_ready" = 1 ] || {
    echo "FAIL: page input focus was not recovered after restore"; exit 1; }

# Locate the fixture marker in screen coordinates, then prove context-menu and
# wheel independently. All pointer input remains untargeted XTEST input.
pointer_position="$(color_center "$FOCUS_PNG" 204 68 204 1000)" || {
    echo "FAIL: could not locate pointer marker in page client area"; exit 1; }
read -r pointer_x pointer_y <<<"$pointer_position"
xdotool mousemove --sync "$pointer_x" "$pointer_y" click 3

context_ready=0
for _ in $(seq 1 "${CONTEXT_ATTEMPTS:-50}"); do
    capture_frame "$CONTEXT_PNG"
    if python3 - "$CONTEXT_PNG" <<'PY'
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert("RGB")
colors = image.getcolors(maxcolors=image.width * image.height) or []
cyan = sum(
    count for count, color in colors
    if all(abs(actual - expected) <= 3
           for actual, expected in zip(color, (0, 170, 170)))
)
raise SystemExit(0 if cyan >= 500 else 1)
PY
    then
        context_ready=1
        break
    fi
    sleep "${CONTEXT_INTERVAL:-0.1}"
done
[ "$context_ready" = 1 ] || {
    echo "FAIL: trusted context-menu marker missing"; exit 1; }

xdotool click 4
wheel_ready=0
for _ in $(seq 1 "${WHEEL_ATTEMPTS:-50}"); do
    capture_frame "$WHEEL_PNG"
    if python3 - "$WHEEL_PNG" <<'PY'
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert("RGB")
colors = image.getcolors(maxcolors=image.width * image.height) or []
orange = sum(
    count for count, color in colors
    if all(abs(actual - expected) <= 3
           for actual, expected in zip(color, (170, 85, 0)))
)
raise SystemExit(0 if orange >= 500 else 1)
PY
    then
        wheel_ready=1
        break
    fi
    sleep "${WHEEL_INTERVAL:-0.1}"
done
[ "$wheel_ready" = 1 ] || {
    echo "FAIL: trusted wheel marker missing"; exit 1; }

quadrants="$(quadrant_count)"
if [ "$quadrants" -lt "${MIN_QUADRANT_RUNS:-50}" ]; then
    echo "FAIL: terminal compositor produced only $quadrants quadrant glyphs"
    exit 1
fi

# The bare-Xorg guest has no window manager to translate _NET_CLOSE_WINDOW.
# Deliver the native Alt+F4 accelerator instead; it must tear down the shell
# rather than leave an invisible Carbonyl process behind. Carbonyl may destroy
# the window before xdotool sends KeyRelease, which makes xdotool report an
# expected BadWindow race; the process-exit and status checks below are the
# authoritative result.
xdotool key --window "$WINDOW_ID" alt+F4 2>/dev/null || true
release_synthetic_modifiers
closed=0
for _ in $(seq 1 "${CLOSE_ATTEMPTS:-100}"); do
    if ! kill -0 "$CARBONYL_PID" 2>/dev/null; then
        closed=1
        break
    fi
    sleep "${CLOSE_INTERVAL:-0.1}"
done
[ "$closed" = 1 ] || {
    echo "FAIL: native Alt+F4 did not terminate Carbonyl"; exit 1; }
if wait "$CARBONYL_PID"; then
    :
else
    close_status=$?
    CARBONYL_PID=""
    echo "FAIL: Carbonyl exited with status $close_status after native Alt+F4"
    exit 1
fi
CARBONYL_PID=""

echo "PASS: resize, post-resize terminal progress, XTEST input, focus recovery, and native Alt+F4 close"
