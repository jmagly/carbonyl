#!/usr/bin/env bash
# test-b64-text.sh — Smoke test for --carbonyl-b64-text mode
#
# Starts a local HTTP server, runs carbonyl with --carbonyl-b64-text against
# a known fixture page, captures terminal output, and asserts specific strings
# appear in the captured text.
#
# Exit 0 on success, 1 on failure.
#
# Usage:
#   bash scripts/test-b64-text.sh              # uses build/pre-built/<triple>/
#   CARBONYL_BIN=/path/to/carbonyl bash scripts/test-b64-text.sh

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")"
cd "$CARBONYL_ROOT"

# ── Locate binary ────────────────────────────────────────────────────────────

if [ -z "${CARBONYL_BIN:-}" ]; then
    triple="$(scripts/platform-triple.sh)"
    CARBONYL_BIN="build/pre-built/$triple/carbonyl"
    export LD_LIBRARY_PATH="build/pre-built/$triple${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

if [ ! -x "$CARBONYL_BIN" ]; then
    echo "FAIL: carbonyl binary not found at $CARBONYL_BIN"
    echo "      Run scripts/build-local.sh first."
    exit 1
fi

# ── Configuration ────────────────────────────────────────────────────────────

FIXTURE="tests/fixtures/b64-text-capture.html"
PORT="${TEST_PORT:-0}"  # 0 = let python pick a free port
CAPTURE_SECONDS="${CAPTURE_SECONDS:-8}"
TMPDIR_BASE="${TMPDIR:-/tmp}"

# Strings that must appear in the captured terminal output.
# These are unique tokens from the fixture HTML.
EXPECTED_STRINGS=(
    "CarbonylTextCaptureTest"
    "SectionAlpha"
    "Foxtrot"
)

# ── Helpers ──────────────────────────────────────────────────────────────────

cleanup() {
    [ -n "${HTTP_PID:-}" ] && kill "$HTTP_PID" 2>/dev/null || true
    [ -n "${CARBONYL_PID:-}" ] && kill "$CARBONYL_PID" 2>/dev/null || true
    [ -n "${WORK_DIR:-}" ] && rm -rf "$WORK_DIR" || true
}
trap cleanup EXIT

WORK_DIR="$(mktemp -d "$TMPDIR_BASE/carbonyl-b64-test.XXXXXX")"

# ── 1. Start HTTP server ────────────────────────────────────────────────────

# Use python3 to serve the fixture directory; write the actual port to a file.
python3 -c "
import http.server, socketserver, sys, os
os.chdir('$CARBONYL_ROOT/tests/fixtures')
handler = http.server.SimpleHTTPRequestHandler
with socketserver.TCPServer(('127.0.0.1', $PORT), handler) as httpd:
    port = httpd.server_address[1]
    with open('$WORK_DIR/port', 'w') as f:
        f.write(str(port))
    print(f'Serving on port {port}', file=sys.stderr)
    httpd.serve_forever()
" &
HTTP_PID=$!

# Wait for port file
for i in $(seq 1 20); do
    [ -f "$WORK_DIR/port" ] && break
    sleep 0.1
done

if [ ! -f "$WORK_DIR/port" ]; then
    echo "FAIL: HTTP server did not start"
    exit 1
fi

ACTUAL_PORT="$(cat "$WORK_DIR/port")"
URL="http://127.0.0.1:${ACTUAL_PORT}/b64-text-capture.html"
echo "==> HTTP server on port $ACTUAL_PORT"

# ── 2. Run carbonyl in a PTY ────────────────────────────────────────────────

echo "==> Running carbonyl --carbonyl-b64-text for ${CAPTURE_SECONDS}s..."

# Use `script` to allocate a PTY and capture terminal output.
CAPTURE_FILE="$WORK_DIR/capture.txt"
STDERR_FILE="$WORK_DIR/stderr.txt"

script -q -c "
    $CARBONYL_BIN \
        --carbonyl-b64-text \
        --no-sandbox \
        --disable-gpu \
        --headless \
        '$URL' \
        2>'$STDERR_FILE'
" "$CAPTURE_FILE" &
CARBONYL_PID=$!

sleep "$CAPTURE_SECONDS"

# Send SIGTERM to carbonyl
kill "$CARBONYL_PID" 2>/dev/null || true
wait "$CARBONYL_PID" 2>/dev/null || true
CARBONYL_PID=""

# ── 3. Check for cppgc/Oilpan assertion failures ────────────────────────────

echo "==> Checking stderr for assertion failures..."

if [ -f "$STDERR_FILE" ] && grep -qiE '(cppgc|oilpan|CHECK failed|FATAL)' "$STDERR_FILE"; then
    echo "FAIL: cppgc/Oilpan assertion or FATAL error detected in stderr:"
    grep -iE '(cppgc|oilpan|CHECK failed|FATAL)' "$STDERR_FILE" | head -5
    exit 1
fi

echo "    No assertion failures in stderr."

# ── 4. Assert expected strings in captured output ────────────────────────────

echo "==> Checking captured text for expected strings..."

# Strip ANSI escape codes from the capture
CLEAN_FILE="$WORK_DIR/clean.txt"
sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$CAPTURE_FILE" > "$CLEAN_FILE" 2>/dev/null || \
    cp "$CAPTURE_FILE" "$CLEAN_FILE"

PASS_COUNT=0
FAIL_COUNT=0

for expected in "${EXPECTED_STRINGS[@]}"; do
    if grep -q "$expected" "$CLEAN_FILE"; then
        echo "    PASS: found '$expected'"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "    FAIL: missing '$expected'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# ── 5. Report ────────────────────────────────────────────────────────────────

echo ""
echo "==> Results: $PASS_COUNT passed, $FAIL_COUNT failed (of ${#EXPECTED_STRINGS[@]} assertions)"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "Captured output (first 50 lines, cleaned):"
    head -50 "$CLEAN_FILE"
    echo ""
    echo "FAIL: b64 text-capture smoke test failed"
    exit 1
fi

echo "PASS: b64 text-capture smoke test passed"
exit 0
