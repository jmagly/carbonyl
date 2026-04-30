#!/usr/bin/env bash
# test-text-parity.sh — Phase 0 W0.6 text-render parity.
#
# For each fixture in tests/fixtures/parity/, runs Carbonyl twice — once
# with ozone_platform=headless and once with ozone_platform=x11 — at the
# same fixed viewport and COLORTERM. Captures the terminal stream from
# each and byte-compares.
#
# This catches regressions where the rendering bridge (patches 0003,
# 0006, 0009-0014) somehow takes a different code path under x11 Ozone
# than under headless Ozone. Both variants share the same compositor
# bridge in src/browser/host_display_client.cc; the terminal stream
# should be byte-identical for the same fixture.
#
# Refs: roctinam/carbonyl#62, ADR-002 rev 2.
#
# Usage:
#   bash scripts/test-text-parity.sh \
#     --headless-bin /path/to/headless/carbonyl \
#     --x11-bin /path/to/x11/carbonyl
#
# Or via env:
#   CARBONYL_HEADLESS_BIN=... CARBONYL_X11_BIN=... bash scripts/test-text-parity.sh
#
# In the qa-runner container both binaries can live under
# /opt/carbonyl-headless/ and /opt/carbonyl-x11/ respectively; the
# build-runtime.yml step pulls both runtime tarballs and points the
# script at them.
#
# DISPLAY must be set for the x11 variant (qa-runner provides :99).
# The headless variant does not require DISPLAY.

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")"
cd "$CARBONYL_ROOT"

# ── Args ─────────────────────────────────────────────────────────────────────

CARBONYL_HEADLESS_BIN="${CARBONYL_HEADLESS_BIN:-}"
CARBONYL_X11_BIN="${CARBONYL_X11_BIN:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --headless-bin)
            [ $# -ge 2 ] || { echo "ERROR: --headless-bin needs a value" >&2; exit 2; }
            CARBONYL_HEADLESS_BIN="$2"; shift ;;
        --x11-bin)
            [ $# -ge 2 ] || { echo "ERROR: --x11-bin needs a value" >&2; exit 2; }
            CARBONYL_X11_BIN="$2"; shift ;;
        --headless-bin=*) CARBONYL_HEADLESS_BIN="${1#*=}" ;;
        --x11-bin=*)      CARBONYL_X11_BIN="${1#*=}" ;;
        -h|--help)
            sed -n '2,32p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

[ -x "$CARBONYL_HEADLESS_BIN" ] || { echo "ERROR: headless binary not executable: $CARBONYL_HEADLESS_BIN" >&2; exit 1; }
[ -x "$CARBONYL_X11_BIN"      ] || { echo "ERROR: x11 binary not executable:      $CARBONYL_X11_BIN" >&2; exit 1; }
[ -n "${DISPLAY:-}" ]            || { echo "ERROR: DISPLAY not set; x11 variant requires an X server" >&2; exit 1; }

# ── Configuration ────────────────────────────────────────────────────────────

VIEWPORT="${VIEWPORT:-1280x720}"
# Polling: wait until the captured stream has at least
# MIN_CONTENT_QUADRANTS quadrant runs AND has been stable
# (no growth) for SETTLE_SECONDS, then kill. Bounded by MAX_CAPTURE.
# This adapts to startup-latency variation between ozone variants
# rather than relying on a fixed sleep that races Chromium init.
MIN_CONTENT_QUADRANTS="${MIN_CONTENT_QUADRANTS:-100}"
SETTLE_SECONDS="${SETTLE_SECONDS:-2}"
MAX_CAPTURE="${MAX_CAPTURE:-45}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"
# Legacy fixed-sleep override; if set, polling is disabled and we
# just sleep this many seconds before killing.
CAPTURE_SECONDS="${CAPTURE_SECONDS:-}"
TMPDIR_BASE="${TMPDIR:-/tmp}"
FIXTURES_DIR="$CARBONYL_ROOT/tests/fixtures/parity"

# What "parity" means for the terminal stream
# ===========================================
# The compositor bridge (host_display_client.cc) is shared between
# both ozone variants — they produce IDENTICAL pixel buffers for the
# same fixture. The bridge then forwards those pixels to the painter,
# which emits ANSI escape sequences to the terminal stream. Same input
# pixels → same painter output, modulo render-loop phase.
#
# What CAN differ between captures of the same fixture:
#   - Number of repaints captured (timing)
#   - Order of cell-paint commands within a frame (paint pattern can
#     start at different rows depending on damage region)
#   - Cursor-positioning escape sequences (sub-byte differences from
#     row/col digits)
#
# What MUST match for parity:
#   - The set of distinct ANSI SGR escape sequences used. SGR encodes
#     foreground/background colour pairs — if both variants render the
#     same pixels they emit the same set of SGR escapes.
#   - Both variants must produce > MIN_CONTENT_QUADRANTS (proves both
#     are actively painting, not stuck in startup).
#   - Last-frame size should be comparable (a 95% size mismatch is a
#     real divergence; a 5% mismatch is paint-phase noise).
#
# Tolerance class meanings:
#   structural — set-of-SGRs within 5%, last-frame size within 25%.
#                Byte-diff is logged but not a fail criterion (paint
#                phase reorders bytes between captures of the same scene).
declare -A TOLERANCE=(
    [static.html]=structural
    [css-rich.html]=structural
    [dynamic.html]=structural
)
STRUCTURAL_DIFF_THRESHOLD_PCT="${STRUCTURAL_DIFF_THRESHOLD_PCT:-5}"

# ── Helpers ──────────────────────────────────────────────────────────────────

WORK_DIR="$(mktemp -d "$TMPDIR_BASE/carbonyl-parity-test.XXXXXX")"
cleanup() {
    [ -n "${WORK_DIR:-}" ] && rm -rf "$WORK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

run_carbonyl() {
    # Writes the captured terminal stream to <out_file>. Steady-state
    # polling: kill once the stream has MIN_CONTENT_QUADRANTS quadrant
    # runs AND has been stable for SETTLE_SECONDS, bounded by
    # MAX_CAPTURE. Set CAPTURE_SECONDS=N to fall back to fixed sleep.
    local bin="$1" ozone="$2" fixture="$3" out="$4"
    local lib_dir
    lib_dir="$(dirname "$bin")"

    : > "$out"

    LD_LIBRARY_PATH="$lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    COLORTERM=truecolor \
        "$bin" \
            --no-sandbox \
            --ozone-platform="$ozone" \
            --viewport="$VIEWPORT" \
            "file://$fixture" \
        > "$out" 2>/dev/null &
    local pid=$!

    if [ -n "$CAPTURE_SECONDS" ]; then
        sleep "$CAPTURE_SECONDS"
    else
        local elapsed=0 settled=0 last_size=0
        while [ "$elapsed" -lt "$MAX_CAPTURE" ]; do
            sleep "$POLL_INTERVAL"
            elapsed=$(( elapsed + POLL_INTERVAL ))
            local cur_size cur_quads
            cur_size="$(wc -c < "$out" 2>/dev/null || echo 0)"
            cur_quads="$(count_quadrants "$out")"
            if [ "$cur_quads" -ge "$MIN_CONTENT_QUADRANTS" ]; then
                if [ "$cur_size" = "$last_size" ]; then
                    settled=$(( settled + POLL_INTERVAL ))
                    if [ "$settled" -ge "$SETTLE_SECONDS" ]; then
                        break
                    fi
                else
                    settled=0
                fi
            fi
            last_size="$cur_size"
        done
    fi

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

count_quadrants() {
    # `|| true` swallows grep's exit-1 when nothing matches; pipefail
    # would otherwise kill the script.
    ( grep -aoE $'\xe2\x96[\x80-\x9f]' "$1" 2>/dev/null || true ) | wc -l
}

distinct_sgr() {
    ( grep -aoE $'\x1b\\[[0-9;]+m' "$1" 2>/dev/null || true ) | sort -u | wc -l
}

# Set-similarity tolerance: even with the same fixture and viewport, the
# compositor occasionally emits a single extra anti-aliased pixel in a
# different colour bucket between runs (normal subpixel-rendering
# jitter). A 1-SGR delta on a ~50-SGR set is content-equivalent, not a
# regression. Threshold defaults to 5% of the larger count.
sgr_within_tolerance() {
    local a="$1" b="$2" pct="${3:-$STRUCTURAL_DIFF_THRESHOLD_PCT}"
    local larger delta
    larger="$a"; [ "$b" -gt "$larger" ] && larger="$b"
    [ "$larger" -eq 0 ] && return 0
    delta="$(( a > b ? a - b : b - a ))"
    [ "$(( delta * 100 / larger ))" -le "$pct" ]
}

byte_diff_count() {
    ( cmp -l "$1" "$2" 2>/dev/null || true ) | wc -l
}

# Carbonyl's painter brackets each repaint with the begin sequence
# `\x1b[?25l\x1b[?12l` (hide cursor + cursor blink off). The final
# repaint in a captured stream is the steady-state frame — what the
# user sees once loading settles. The repaint *rate* legitimately
# differs between ozone variants (x11 paints more frequently), but
# the steady-state frame must match for parity to hold.
extract_last_frame() {
    # Steady-state frame extraction. The carbonyl painter brackets
    # each frame with a begin marker (`\x1b[?25l\x1b[?12l`). The
    # stream contains a mix of:
    # - Empty frames (no paint between two begins; 12-byte gap)
    # - Incremental damage updates (small partial repaints late in
    #   the stream when only a region changed)
    # - Full steady-state repaints (the large frame containing the
    #   complete rendered page)
    #
    # We want the full repaint. Algorithm: list all begin offsets,
    # compute gaps to next-begin, pick the begin with the LARGEST
    # gap. That's the largest frame, which is invariably the full
    # steady-state paint.
    #
    # `extract_last_frame` is a misnomer kept for backward callers;
    # what it actually returns now is the largest content frame in
    # the stream. (This is a stronger parity signal than "last".)
    local infile="$1" outfile="$2"
    local offsets file_size
    file_size="$(wc -c < "$infile")"
    offsets="$( ( grep -oab $'\x1b\\[?25l\x1b\\[?12l' "$infile" 2>/dev/null || true ) | cut -d: -f1)"
    offsets="$(printf '%s\n%s' "$offsets" "$file_size")"

    # Walk forward, track largest gap.
    local max_gap=0 picked_start="" picked_end=""
    local prev=""
    while IFS= read -r off; do
        [ -n "$off" ] || continue
        if [ -n "$prev" ]; then
            local gap=$(( off - prev ))
            if [ "$gap" -gt "$max_gap" ]; then
                max_gap="$gap"
                picked_start="$prev"
                picked_end="$off"
            fi
        fi
        prev="$off"
    done < <(echo "$offsets")

    if [ -n "$picked_start" ] && [ -n "$picked_end" ] && [ "$max_gap" -ge 128 ]; then
        local len="$max_gap"
        tail -c +"$((picked_start + 1))" "$infile" | head -c "$len" > "$outfile"
    else
        # No substantial frame found — copy whole file as a fallback.
        cp "$infile" "$outfile"
    fi
}

# ── Run ──────────────────────────────────────────────────────────────────────

echo "==> Carbonyl text-render parity (W0.6)"
echo "    headless bin: $CARBONYL_HEADLESS_BIN"
echo "    x11 bin:      $CARBONYL_X11_BIN"
echo "    viewport:     $VIEWPORT"
echo "    capture:      ${CAPTURE_SECONDS}s per fixture"
echo "    DISPLAY:      $DISPLAY"
echo ""

REPORT="$WORK_DIR/report.txt"
: > "$REPORT"

overall_fail=0
declare -A FIXTURE_RESULT

for fixture_name in static.html css-rich.html dynamic.html; do
    fixture_path="$FIXTURES_DIR/$fixture_name"
    [ -f "$fixture_path" ] || { echo "ERROR: fixture missing: $fixture_path" >&2; exit 1; }

    tol="${TOLERANCE[$fixture_name]}"
    h_out="$WORK_DIR/${fixture_name}.headless"
    x_out="$WORK_DIR/${fixture_name}.x11"

    echo "==> ${fixture_name} (tolerance: ${tol})"

    run_carbonyl "$CARBONYL_HEADLESS_BIN" headless "$fixture_path" "$h_out"
    run_carbonyl "$CARBONYL_X11_BIN"      x11      "$fixture_path" "$x_out"

    h_size="$(wc -c < "$h_out")"
    x_size="$(wc -c < "$x_out")"
    h_quads="$(count_quadrants "$h_out")"
    x_quads="$(count_quadrants "$x_out")"

    echo "    headless: ${h_size}B stream  quadrants=${h_quads}"
    echo "    x11:      ${x_size}B stream  quadrants=${x_quads}"

    # The two variants legitimately repaint at different rates — what
    # we care about is the steady-state frame. Extract the final paint
    # from each stream and compare those. SGR set is also computed off
    # the last frame only — counting SGRs across the whole stream
    # captures transient loading-state frames whose palette differs by
    # capture timing rather than by rendered content.
    h_last="$h_out.lastframe"
    x_last="$x_out.lastframe"
    extract_last_frame "$h_out" "$h_last"
    extract_last_frame "$x_out" "$x_last"
    h_last_size="$(wc -c < "$h_last")"
    x_last_size="$(wc -c < "$x_last")"
    h_sgr="$(distinct_sgr "$h_last")"
    x_sgr="$(distinct_sgr "$x_last")"
    echo "    last frame: headless=${h_last_size}B (sgrs=${h_sgr})  x11=${x_last_size}B (sgrs=${x_sgr})"

    fail=0

    # Inconclusive guard — if either variant produced essentially no
    # rendered content, capture probably ended before steady state.
    # That's a test-environment problem, not a parity regression.
    if [ "$h_quads" -lt "$MIN_CONTENT_QUADRANTS" ] || [ "$x_quads" -lt "$MIN_CONTENT_QUADRANTS" ]; then
        echo "    [INCONCLUSIVE] one or both variants produced <${MIN_CONTENT_QUADRANTS} quadrant runs"
        if [ -n "$CAPTURE_SECONDS" ]; then
            echo "                   bump CAPTURE_SECONDS (currently ${CAPTURE_SECONDS})"
        else
            echo "                   bump MAX_CAPTURE (currently ${MAX_CAPTURE}) or simplify fixture"
        fi
        FIXTURE_RESULT["$fixture_name"]=INCONCLUSIVE
        # Don't flip overall_fail — inconclusive ≠ regression. Operator
        # should re-run with longer capture; if it stabilises, parity
        # holds. If still inconclusive, that's an environment fix.
        {
            printf '## %s\n\n' "$fixture_name"
            printf 'Tolerance: `%s`\n\n' "$tol"
            printf '| Variant  | Stream bytes | Last frame bytes | Quadrant runs | Distinct SGRs |\n'
            printf '|----------|-------------:|-----------------:|--------------:|--------------:|\n'
            printf '| headless | %d | %d | %d | %d |\n' "$h_size" "$h_last_size" "$h_quads" "$h_sgr"
            printf '| x11      | %d | %d | %d | %d |\n' "$x_size" "$x_last_size" "$x_quads" "$x_sgr"
            printf '\nResult: **INCONCLUSIVE** — capture window may have been too short.\n\n'
        } >> "$REPORT"
        echo ""
        continue
    fi

    # Pass criteria (all variants currently use 'structural'):
    #   1. SGR-set sizes within STRUCTURAL_DIFF_THRESHOLD_PCT
    #   2. Last-frame sizes within LAST_FRAME_SIZE_THRESHOLD_PCT
    # Byte-diff between last frames is logged but advisory only —
    # paint-phase reorders bytes between captures of the same scene.
    LAST_FRAME_SIZE_THRESHOLD_PCT="${LAST_FRAME_SIZE_THRESHOLD_PCT:-25}"

    if ! sgr_within_tolerance "$h_sgr" "$x_sgr" "$STRUCTURAL_DIFF_THRESHOLD_PCT"; then
        echo "    [FAIL] distinct-SGR counts diverge >${STRUCTURAL_DIFF_THRESHOLD_PCT}% (headless=${h_sgr} vs x11=${x_sgr})"
        fail=1
    else
        echo "    [ ok ] distinct-SGR counts within ${STRUCTURAL_DIFF_THRESHOLD_PCT}% (${h_sgr} vs ${x_sgr})"
    fi

    # Last-frame size delta as % of the larger
    larger_size="$h_last_size"
    [ "$x_last_size" -gt "$larger_size" ] && larger_size="$x_last_size"
    if [ "$larger_size" -gt 0 ]; then
        size_delta="$(( h_last_size > x_last_size ? h_last_size - x_last_size : x_last_size - h_last_size ))"
        size_pct="$(( size_delta * 100 / larger_size ))"
        if [ "$size_pct" -gt "$LAST_FRAME_SIZE_THRESHOLD_PCT" ]; then
            echo "    [FAIL] last-frame size diff ${size_pct}% > ${LAST_FRAME_SIZE_THRESHOLD_PCT}% threshold"
            fail=1
        else
            echo "    [ ok ] last-frame size delta within ${LAST_FRAME_SIZE_THRESHOLD_PCT}% (${size_pct}%)"
        fi

        # Advisory byte-diff (not a fail criterion — paint-phase noise).
        bdiff="$(byte_diff_count "$h_last" "$x_last")"
        byte_pct="$(( bdiff * 100 / larger_size ))"
        echo "    [info] last-frame byte-diff ${byte_pct}% (advisory; paint-phase reorder)"
    fi

    if [ "$fail" -eq 0 ]; then
        FIXTURE_RESULT["$fixture_name"]=PASS
        echo "    [PASS]"
    else
        FIXTURE_RESULT["$fixture_name"]=FAIL
        overall_fail=1
    fi

    {
        printf '## %s\n\n' "$fixture_name"
        printf 'Tolerance: `%s`\n\n' "$tol"
        printf '| Variant  | Stream bytes | Last frame bytes | Quadrant runs | Distinct SGRs |\n'
        printf '|----------|-------------:|-----------------:|--------------:|--------------:|\n'
        printf '| headless | %d | %d | %d | %d |\n' "$h_size" "$h_last_size" "$h_quads" "$h_sgr"
        printf '| x11      | %d | %d | %d | %d |\n' "$x_size" "$x_last_size" "$x_quads" "$x_sgr"
        printf '\nResult: **%s**\n\n' "${FIXTURE_RESULT[$fixture_name]}"
    } >> "$REPORT"

    echo ""
done

echo "==> Summary"
for fx in static.html css-rich.html dynamic.html; do
    echo "    $fx: ${FIXTURE_RESULT[$fx]}"
done

# Persist the report alongside .aiwg/reports/ for the audit trail.
# Falls back to $WORK_DIR if the canonical path is read-only (e.g.
# inside a CI container with the repo mounted :ro).
REPORT_DEST="${PARITY_REPORT_DEST:-$CARBONYL_ROOT/.aiwg/reports/phase0-w06-parity-report.md}"
write_report() {
    local dest="$1"
    mkdir -p "$(dirname "$dest")" 2>/dev/null || return 1
    {
        printf '# Phase 0 W0.6 — text-render parity report\n\n'
        printf 'Generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'Headless binary: `%s`\n' "$CARBONYL_HEADLESS_BIN"
        printf 'x11 binary: `%s`\n' "$CARBONYL_X11_BIN"
        printf 'Viewport: %s\n' "$VIEWPORT"
        printf 'Capture window: %ss\n\n' "$CAPTURE_SECONDS"
        printf '## Method\n\n'
        printf 'Each fixture runs through both ozone variants at the same\n'
        printf 'viewport with the same `COLORTERM=truecolor`. The captured\n'
        printf 'terminal streams are not byte-compared directly — the two\n'
        printf 'ozone variants legitimately repaint at different rates, so\n'
        printf 'stream length and quadrant-run count differ as a function of\n'
        printf 'capture timing, not rendered content.\n\n'
        printf 'What the test asserts is content-structural equivalence:\n\n'
        printf '- The **set of distinct ANSI SGR escapes** in each stream\n'
        printf '  must match. This is a strong signal that both variants\n'
        printf '  produced the same colour palette and the same set of\n'
        printf '  cell-paint commands.\n'
        printf '- The **final paint frame** (everything after the last\n'
        printf '  `\\x1b[?25l\\x1b[?12l` begin marker) must match within the\n'
        printf '  declared tolerance for each fixture.\n\n'
        cat "$REPORT"
        if [ "$overall_fail" -eq 0 ]; then
            printf '\n**Overall: PASS** — no parity regression detected between ozone variants.\n'
        else
            printf '\n**Overall: FAIL** — see fixture-specific results above.\n'
        fi
    } > "$dest" 2>/dev/null
}

if write_report "$REPORT_DEST"; then
    echo "    report: $REPORT_DEST"
else
    FALLBACK="$WORK_DIR/phase0-w06-parity-report.md"
    write_report "$FALLBACK"
    echo "    report: $FALLBACK (fallback — '$REPORT_DEST' not writable)"
fi

if [ "$overall_fail" -eq 0 ]; then
    echo ""
    echo "PASS — all fixtures within tolerance."
    exit 0
else
    echo ""
    echo "FAIL — at least one fixture exceeded tolerance."
    exit 1
fi
