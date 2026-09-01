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
FLUSH_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"

cleanup() {
    if [ -n "${SERVER_PID:-}" ]; then
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    if [ -z "${KEEP_WORK_DIR:-}" ]; then
        rm -rf -- "$WORK_DIR"
    fi
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

assert_authenticated_flush() {
    python3 - "$1" "$FLUSH_TOKEN" <<'PY'
import json
import pathlib
import sys

prefix = "CARBONYL_STORAGE_FLUSH_RESULT="
log_path = pathlib.Path(sys.argv[1])
expected_token = sys.argv[2]
payloads = [
    line.split(prefix, 1)[1].strip()
    for line in log_path.read_text(errors="replace").splitlines()
    if prefix in line
]
if not payloads:
    raise SystemExit(f"FAIL: no storage-flush result in {log_path}")
try:
    result = json.loads(payloads[-1])
except json.JSONDecodeError as exc:
    raise SystemExit(f"FAIL: malformed storage-flush result in {log_path}: {exc}") from exc
if result.get("schema_version") != 1 or result.get("state") != "stopped":
    raise SystemExit(f"FAIL: invalid storage-flush state in {log_path}")
if result.get("result") != "complete":
    raise SystemExit(f"FAIL: storage flush was not complete in {log_path}")
if result.get("token") != expected_token:
    raise SystemExit(f"FAIL: storage-flush token mismatch in {log_path}")
partitions = result.get("partitions")
acknowledged = result.get("acknowledged")
if not isinstance(partitions, int) or partitions < 0 or acknowledged != partitions:
    raise SystemExit(f"FAIL: inconsistent storage-flush counts in {log_path}")
PY
}

"$CARBONYL_BIN" --user-data-dir="$PROFILE_DIR" --dump-text=dom \
    --carbonyl-storage-flush-token="$FLUSH_TOKEN" \
    --idle=500 --max-wait=15000 "$URL" >"$FIRST_LOG" 2>&1
grep -q 'CARBONYL_STORAGE_INITIALIZED' "$FIRST_LOG"
assert_authenticated_flush "$FIRST_LOG"

"$CARBONYL_BIN" --user-data-dir="$PROFILE_DIR" --dump-text=dom \
    --carbonyl-storage-flush-token="$FLUSH_TOKEN" \
    --idle=500 --max-wait=15000 "$URL" >"$SECOND_LOG" 2>&1
grep -q 'CARBONYL_STORAGE_RESTORED' "$SECOND_LOG"
assert_authenticated_flush "$SECOND_LOG"

echo "PASS: acknowledged shutdown preserved synthetic cookie and localStorage markers"
