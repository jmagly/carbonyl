#!/usr/bin/env bash
# capture.sh — issue #87 full-page-capture verification.
#
# For each test URL, capture two X-mirror frames from the SAME x11-capable
# carbonyl runtime:
#   before : --viewport=1280x800                     -> frame ~800px tall
#   after  : --viewport=1280x800 --page-height=4000  -> frame up to 4000px tall
#
# The X-mirror window is `cells*(2,4)` px, so we launch carbonyl under a LARGE
# PTY (ptycap.py forces a 640x1001 winsize) to make the window 1280x4000 — big
# enough to show the full `after` page. Chromium's compositor frame is sized to
# window.browser (the CSS viewport); --page-height enlarges only the height, so
# `after` fills the window while `before` fills only its top 800px.
#
# Capture uses ffmpeg x11grab (scrot is not assumed present). Frames -> out/<host>/
# {before,after}.png; analyze.py then measures rendered-content extent.
#
# REQUIREMENTS:
#   - Xvfb, ffmpeg, python3 + Pillow.
#   - An x11-capable post-#226 runtime that ALSO carries chromium patch 0029
#     (commit 2f49034). Point CARBONYL_BIN at it. The bundled alpha.1 runtime is
#     too old. The `runtime-x11-<hash>` published by build-runtime on post-#226
#     main is correct.
#   - A host where carbonyl renders page TEXT. A GPU-less Xvfb with only the
#     SwiftShader fallback may paint the page background but little text — that
#     produces near-empty captures for BOTH before and after (an environment
#     limit, not a regression). Use a GL-capable host or the CI capture env.
#
# Exit 0 if all captures were produced; analysis verdict is printed by analyze.py.

set -euo pipefail

HERE="$(cd "$(dirname -- "$0")" && pwd)"
cd "$HERE"

: "${CARBONYL_BIN:?Set CARBONYL_BIN to an x11-capable post-#226 carbonyl (see README)}"
[ -x "$CARBONYL_BIN" ] || { echo "FAIL: \$CARBONYL_BIN not executable: $CARBONYL_BIN"; exit 1; }
RT_DIR="$(cd "$(dirname -- "$CARBONYL_BIN")" && pwd)"
export LD_LIBRARY_PATH="$RT_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

for cmd in Xvfb ffmpeg python3; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: $cmd not on PATH"; exit 1; }
done

# ── Config ───────────────────────────────────────────────────────────────────
VW="${VW:-1280x800}"             # the "before" viewport (the clip)
PAGE_HEIGHT="${PAGE_HEIGHT:-4000}"
PTY_COLS="${PTY_COLS:-640}"      # 640*2 = 1280 px wide window
PTY_ROWS="${PTY_ROWS:-1001}"     # ~1000*4 = 4000 px tall window
GRAB_W="${GRAB_W:-1280}"
GRAB_H="${GRAB_H:-4000}"
SCREEN_W="${SCREEN_W:-1300}"
SCREEN_H="${SCREEN_H:-4100}"
SETTLE="${SETTLE:-15}"           # PTY lifetime; grab fires at SETTLE-5
GRAB_AT="${GRAB_AT:-10}"
DISP="${DISP:-:96}"

URLS=(
    "https://example.com"
    "https://news.ycombinator.com"
    "https://en.wikipedia.org/wiki/Headless_browser"
    "https://github.com/jmagly/carbonyl"
)

OUT="$HERE/out"; rm -rf "$OUT"; mkdir -p "$OUT"

echo "==> Xvfb $DISP @ ${SCREEN_W}x${SCREEN_H}x24"
Xvfb "$DISP" -screen 0 "${SCREEN_W}x${SCREEN_H}x24" -nolisten tcp >/dev/null 2>&1 &
XVFB_PID=$!
cleanup() { kill -TERM "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1

host_slug() { echo "$1" | sed -E 's#^https?://##; s#[/?].*$##; s#[^A-Za-z0-9._-]#_#g'; }

# capture <url> <outfile> <extra-flags...>
capture() {
    local url="$1" outfile="$2"; shift 2
    DISPLAY="$DISP" python3 "$HERE/ptycap.py" "$PTY_COLS" "$PTY_ROWS" "$SETTLE" \
        "$CARBONYL_BIN" -- --no-sandbox --ozone-platform=x11 --viewport="$VW" "$@" "$url" \
        >/dev/null 2>&1 &
    local pid=$!
    sleep "$GRAB_AT"
    ffmpeg -loglevel error -y -f x11grab -video_size "${GRAB_W}x${GRAB_H}" \
        -i "$DISP" -frames:v 1 "$outfile" </dev/null || true
    wait "$pid" 2>/dev/null || true
    [ -s "$outfile" ] || { echo "FAIL: empty capture: $outfile"; exit 1; }
}

for url in "${URLS[@]}"; do
    slug="$(host_slug "$url")"
    dir="$OUT/$slug"; mkdir -p "$dir"
    echo "==> $url"
    echo "    [before] --viewport=$VW"
    capture "$url" "$dir/before.png"
    echo "    [after]  --viewport=$VW --page-height=$PAGE_HEIGHT"
    capture "$url" "$dir/after.png" --page-height="$PAGE_HEIGHT"
done

echo "==> Analysis"
python3 "$HERE/analyze.py" "$OUT" "${VW##*x}"
