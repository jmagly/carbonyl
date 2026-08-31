#!/usr/bin/env bash
# Deterministic local persistence probe for acknowledged shutdown (#292).

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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/carbonyl-storage-flush.XXXXXX")"
PROFILE_DIR="$WORK_DIR/profile"
FIRST_LOG="$WORK_DIR/first.log"
SECOND_LOG="$WORK_DIR/second.log"
PORT_FILE="$WORK_DIR/port"

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill -TERM "$SERVER_PID" 2>/dev/null || true
    [ -n "${SERVER_PID:-}" ] && wait "$SERVER_PID" 2>/dev/null || true
    [ -z "${KEEP_WORK_DIR:-}" ] && rm -rf "$WORK_DIR" || true
}
trap cleanup EXIT

python3 - "$CARBONYL_ROOT/tests/fixtures" "$PORT_FILE" <<'PY' &
import http.server
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
port_file = pathlib.Path(sys.argv[2])
os.chdir(root)
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler)
port_file.write_text(str(server.server_port))
server.serve_forever()
PY
SERVER_PID=$!

for _ in $(seq 1 100); do
    [ -s "$PORT_FILE" ] && break
    sleep 0.05
done
[ -s "$PORT_FILE" ] || { echo "FAIL: fixture server did not start"; exit 1; }
URL="http://127.0.0.1:$(cat "$PORT_FILE")/storage-flush.html"

"$CARBONYL_BIN" --user-data-dir="$PROFILE_DIR" --dump-text=dom \
    --idle=500 --max-wait=15000 "$URL" >"$FIRST_LOG" 2>&1
grep -q 'CARBONYL_STORAGE_INITIALIZED' "$FIRST_LOG"
grep -q 'CARBONYL_STORAGE_FLUSH_RESULT=.*"result":"complete"' "$FIRST_LOG"

"$CARBONYL_BIN" --user-data-dir="$PROFILE_DIR" --dump-text=dom \
    --idle=500 --max-wait=15000 "$URL" >"$SECOND_LOG" 2>&1
grep -q 'CARBONYL_STORAGE_RESTORED' "$SECOND_LOG"
grep -q 'CARBONYL_STORAGE_FLUSH_RESULT=.*"result":"complete"' "$SECOND_LOG"

echo "PASS: acknowledged shutdown preserved synthetic cookie and localStorage markers"
