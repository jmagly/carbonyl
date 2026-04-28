#!/usr/bin/env bash
# test-x-mirror.sh — Dual-output smoke test for CARBONYL_X_MIRROR.
#
# Asserts that a single Carbonyl process simultaneously produces:
#   1. Terminal render — ANSI escape sequences on stdout containing the
#      fixture's marker token (proves the existing bridge path still
#      works end-to-end).
#   2. X-window render — a non-blank framebuffer on $DISPLAY whose pixel
#      histogram contains the fixture's blue background + red banner
#      colours in expected proportions (proves x_mirror.cc routes
#      compositor frames to libX11).
#
# Run inside the qa-runner container (Xorg + scrot + python3-PIL +
# carbonyl on PATH). Outside the container, set CARBONYL_BIN, ensure
# DISPLAY points at a running X server with PIL available, and provide
# /usr/bin/scrot.
#
# Exit 0 on success, 1 on failure. Prints a one-line summary either way.
#
# References: roctinam/carbonyl#63 (X-mirror), #62 (text-render parity).

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")"
cd "$CARBONYL_ROOT"

# ── Locate carbonyl binary ───────────────────────────────────────────────────

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

: "${DISPLAY:?DISPLAY must be set (run inside the qa-runner container, or start Xorg/Xvfb first)}"

for cmd in scrot python3; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "FAIL: $cmd not on PATH (qa-runner image provides it)"; exit 1; }
done

# ── Configuration ────────────────────────────────────────────────────────────

FIXTURE="$CARBONYL_ROOT/tests/fixtures/x-mirror.html"
[ -f "$FIXTURE" ] || { echo "FAIL: fixture missing: $FIXTURE"; exit 1; }

CAPTURE_SECONDS="${CAPTURE_SECONDS:-10}"
TMPDIR_BASE="${TMPDIR:-/tmp}"

# Pixel-count thresholds. The fixture has a 1920×1080-ish banner of
# #aa0000 and a generous #003366 background. We expect at least a
# few thousand of each — well above any noise floor while leaving
# headroom for Carbonyl's terminal-derived viewport sizing.
MIN_BG_PIXELS="${MIN_BG_PIXELS:-5000}"
MIN_BANNER_PIXELS="${MIN_BANNER_PIXELS:-3000}"

# What we expect in the terminal stream. Carbonyl rasterises every page to
# Unicode quadrant block characters with ANSI colour escapes; raw HTML text
# does NOT appear in the byte stream (use --carbonyl-b64-text for that, see
# test-b64-text.sh). So we assert structural markers instead:
#   - quadrant block U+2580–U+259F encoded as UTF-8 (e.g. ▄ = e2 96 84)
#   - the fixture's two distinctive colours expressed as 24-bit ANSI SGR
#     when truecolor is on, or as nearest 256-colour codes otherwise
MIN_QUADRANT_RUNS="${MIN_QUADRANT_RUNS:-50}"

# Truecolor SGR for the fixture's signature colours. Carbonyl's painter
# emits both foreground (38;2) and background (48;2) — quadrant cells
# carry two colours each — so we accept either form.
COLOR_BG_TRUECOLOR="\x1b\\[[34]8;2;0;51;102"     # #003366 background
COLOR_BANNER_TRUECOLOR="\x1b\\[[34]8;2;170;0;0"  # #aa0000 banner
# Nearest 256-colour fallbacks (xterm palette indices ~17 and ~124),
# in case truecolor probing fails for some reason.
COLOR_BG_256="\x1b\\[[34]8;5;1[78]"
COLOR_BANNER_256="\x1b\\[[34]8;5;12[45]"

WORK_DIR="$(mktemp -d "$TMPDIR_BASE/carbonyl-xmirror-test.XXXXXX")"
TERM_LOG="$WORK_DIR/terminal.log"
FRAME_PNG="$WORK_DIR/frame.png"

cleanup() {
    [ -n "${CARBONYL_PID:-}" ] && kill -TERM "$CARBONYL_PID" 2>/dev/null || true
    [ -n "${CARBONYL_PID:-}" ] && wait "$CARBONYL_PID" 2>/dev/null || true
    [ -n "${WORK_DIR:-}" ] && [ -z "${KEEP_WORK_DIR:-}" ] && rm -rf "$WORK_DIR" || true
}
trap cleanup EXIT

# ── 1. Launch Carbonyl with X-mirror enabled ─────────────────────────────────

echo "==> Launching Carbonyl ($CARBONYL_BIN)"
echo "    DISPLAY=$DISPLAY"
echo "    fixture=file://$FIXTURE"
echo "    work_dir=$WORK_DIR"

# COLORTERM=truecolor enables the 24-bit ANSI SGR path in Carbonyl's
# painter — keeps the colour-escape assertions deterministic regardless
# of the host terminal's reported capabilities.
# --viewport pins CSS layout to a fixed size so the fixture's banner is
# always within the rendered area regardless of how Carbonyl probes the
# (possibly absent) controlling terminal in a container.
# COLORTERM=truecolor forces 24-bit ANSI SGR in the painter so the colour
# escape assertions don't depend on host palette detection.
CARBONYL_X_MIRROR=1 \
COLORTERM=truecolor \
    "$CARBONYL_BIN" \
        --no-sandbox \
        --ozone-platform=x11 \
        --viewport=1280x720 \
        "file://$FIXTURE" \
    > "$TERM_LOG" 2>&1 &
CARBONYL_PID=$!

echo "    pid=$CARBONYL_PID, capturing for ${CAPTURE_SECONDS}s.."
sleep "$CAPTURE_SECONDS"

# ── 2. Capture X framebuffer ─────────────────────────────────────────────────

echo "==> Capturing X framebuffer (scrot)"
scrot "$FRAME_PNG"
[ -s "$FRAME_PNG" ] || { echo "FAIL: scrot produced empty file"; exit 1; }

# Stop the browser before assertions so log files are flushed.
kill -TERM "$CARBONYL_PID" 2>/dev/null || true
wait "$CARBONYL_PID" 2>/dev/null || true
unset CARBONYL_PID

# ── 3. Assert terminal output ────────────────────────────────────────────────

echo "==> Checking terminal output ($(wc -c < "$TERM_LOG") bytes captured)"
fail_terminal=0

# Count quadrant block characters (U+2580–U+259F = e2 96 80 .. e2 96 9f).
# `|| true` — grep exits 1 when nothing matches; pipefail would abort.
quadrant_runs="$( (grep -aoE $'\xe2\x96[\x80-\x9f]' "$TERM_LOG" || true) | wc -l )"
if [ "$quadrant_runs" -lt "$MIN_QUADRANT_RUNS" ]; then
    echo "    [FAIL] only $quadrant_runs quadrant block runs (need $MIN_QUADRANT_RUNS+) — terminal pipeline not painting"
    fail_terminal=1
else
    echo "    [ ok ] $quadrant_runs quadrant block runs (>= $MIN_QUADRANT_RUNS)"
fi

# Expect at least one SGR matching the fixture's background colour.
if grep -aqE "$(printf "%b" "$COLOR_BG_TRUECOLOR")|$(printf "%b" "$COLOR_BG_256")" "$TERM_LOG"; then
    echo "    [ ok ] terminal contains background colour SGR (#003366 or 256-colour fallback)"
else
    echo "    [FAIL] terminal missing background colour SGR for #003366"
    fail_terminal=1
fi

# Expect at least one SGR matching the fixture's banner colour.
if grep -aqE "$(printf "%b" "$COLOR_BANNER_TRUECOLOR")|$(printf "%b" "$COLOR_BANNER_256")" "$TERM_LOG"; then
    echo "    [ ok ] terminal contains banner colour SGR (#aa0000 or 256-colour fallback)"
else
    echo "    [FAIL] terminal missing banner colour SGR for #aa0000"
    fail_terminal=1
fi

# ── 4. Assert X framebuffer ──────────────────────────────────────────────────

echo "==> Checking X framebuffer pixel histogram"
hist="$(python3 - "$FRAME_PNG" "$MIN_BG_PIXELS" "$MIN_BANNER_PIXELS" <<'PY'
import sys
from PIL import Image

path, min_bg, min_banner = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
img = Image.open(path).convert("RGB")
w, h = img.size

# Allow ±2 per channel for AA / dither tolerance.
def near(target, tol=2):
    tr, tg, tb = target
    return lambda r, g, b: abs(r - tr) <= tol and abs(g - tg) <= tol and abs(b - tb) <= tol

bg     = near((0,   51, 102))    # #003366
banner = near((170,  0,   0))    # #aa0000

bg_count = banner_count = total = 0
for count, (r, g, b) in img.getcolors(maxcolors=w * h):
    total += count
    if bg(r, g, b):     bg_count     += count
    if banner(r, g, b): banner_count += count

print(f"size={w}x{h} total={total} bg={bg_count} banner={banner_count} "
      f"bg_ok={bg_count >= min_bg} banner_ok={banner_count >= min_banner}")
sys.exit(0 if (bg_count >= min_bg and banner_count >= min_banner) else 1)
PY
)"
hist_status=$?
echo "    $hist"

# ── 5. Verdict ───────────────────────────────────────────────────────────────

if [ "$fail_terminal" -ne 0 ] || [ "$hist_status" -ne 0 ]; then
    echo ""
    echo "FAIL — dual-output test did not pass."
    echo "       terminal_ok=$([ $fail_terminal -eq 0 ] && echo yes || echo no)"
    echo "       framebuffer_ok=$([ $hist_status -eq 0 ] && echo yes || echo no)"
    [ -n "${KEEP_WORK_DIR:-}" ] && echo "       artefacts kept at $WORK_DIR"
    exit 1
fi

echo ""
echo "PASS — terminal render and X framebuffer both contain expected content."
