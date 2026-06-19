#!/usr/bin/env bash
# capture.sh — issue #87 full-page-capture verification.
#
# For each test URL, capture two X-mirror frames from the SAME x11-capable
# carbonyl runtime:
#   before : --viewport=1280x800                 -> page rastered ~800px tall
#   after  : --viewport=1280x800 --page-height=4000 -> page rastered up to 4000px
#
# The X-mirror window mirrors Chromium's compositor frame, so its height tracks
# window.browser (the CSS viewport). With chromium patch 0029 the X11 ozone
# screen honours that size, so `after` is taller and contains below-the-fold
# content that `before` never rastered.
#
# Capture uses ffmpeg x11grab (scrot is not assumed present). Frames are written
# to out/<host>/{before,after}.png; analyze.py then measures content extent.
#
# REQUIREMENTS: Xvfb, ffmpeg, an x11-capable post-#226 runtime (see README —
# the runtime MUST include chromium patch 0029, commit 2f49034). Point
# CARBONYL_BIN at it.
#
# Exit 0 if all captures were produced; analysis verdict is printed by analyze.py.

set -euo pipefail

HERE="$(cd "$(dirname -- "$0")" && pwd)"
cd "$HERE"

# ── Locate runtime ───────────────────────────────────────────────────────────
: "${CARBONYL_BIN:?Set CARBONYL_BIN to an x11-capable post-#226 carbonyl (see README)}"
[ -x "$CARBONYL_BIN" ] || { echo "FAIL: \$CARBONYL_BIN not executable: $CARBONYL_BIN"; exit 1; }
RT_DIR="$(cd "$(dirname -- "$CARBONYL_BIN")" && pwd)"
export LD_LIBRARY_PATH="$RT_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

for cmd in Xvfb ffmpeg python3; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: $cmd not on PATH"; exit 1; }
done

# ── Config ───────────────────────────────────────────────────────────────────
VW_WIDTH="${VW_WIDTH:-1280}"
VW_HEIGHT="${VW_HEIGHT:-800}"        # the "before" viewport height (the clip)
PAGE_HEIGHT="${PAGE_HEIGHT:-4000}"   # the "after" --page-height
SCREEN_W="${SCREEN_W:-1300}"
SCREEN_H="${SCREEN_H:-4200}"         # tall enough to hold the 4000px "after" window
SETTLE="${SETTLE:-9}"                # seconds to let the page load + paint
DISP="${DISP:-:97}"

URLS=(
    "https://example.com"
    "https://news.ycombinator.com"
    "https://en.wikipedia.org/wiki/Headless_browser"
    "https://github.com/jmagly/carbonyl"
)

OUT="$HERE/out"
rm -rf "$OUT"; mkdir -p "$OUT"

# ── Xvfb ─────────────────────────────────────────────────────────────────────
echo "==> Xvfb $DISP @ ${SCREEN_W}x${SCREEN_H}x24"
Xvfb "$DISP" -screen 0 "${SCREEN_W}x${SCREEN_H}x24" -nolisten tcp >/dev/null 2>&1 &
XVFB_PID=$!
cleanup() { kill -TERM "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1

host_slug() { echo "$1" | sed -E 's#^https?://##; s#[/?].*$##; s#[^A-Za-z0-9._-]#_#g'; }

# capture <label> <url> <outfile> <extra-flags...>
capture() {
    local label="$1" url="$2" outfile="$3"; shift 3
    echo "    [$label] $url"
    CARBONYL_X_MIRROR=1 DISPLAY="$DISP" \
        "$CARBONYL_BIN" --no-sandbox --ozone-platform=x11 \
            --viewport="${VW_WIDTH}x${VW_HEIGHT}" "$@" "$url" \
            >/dev/null 2>&1 &
    local pid=$!
    sleep "$SETTLE"
    # Single full-screen grab; the carbonyl window maps at the origin.
    ffmpeg -loglevel error -y -f x11grab -video_size "${SCREEN_W}x${SCREEN_H}" \
        -i "$DISP" -frames:v 1 "$outfile" </dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    [ -s "$outfile" ] || { echo "FAIL: empty capture: $outfile"; exit 1; }
}

for url in "${URLS[@]}"; do
    slug="$(host_slug "$url")"
    dir="$OUT/$slug"; mkdir -p "$dir"
    echo "==> $url"
    capture before "$url" "$dir/before.png"
    capture after  "$url" "$dir/after.png" --page-height="$PAGE_HEIGHT"
done

echo "==> Analysis"
python3 "$HERE/analyze.py" "$OUT" "$VW_HEIGHT"
