#!/usr/bin/env bash

set -euo pipefail

: "${CARBONYL_BIN:?set CARBONYL_BIN to the checksummed Carbonyl artifact}"
: "${CARBONYL_DISPOSABLE_BROWSER_QA:?set to 1 only inside the disposable browser-QA guest}"

if [ "$CARBONYL_DISPOSABLE_BROWSER_QA" != 1 ]; then
  echo "refusing browser execution outside the disposable browser-QA guest" >&2
  exit 2
fi

# shellcheck disable=SC1091
. /etc/os-release
if [ "${VERSION_ID:-}" != "26.04" ]; then
  echo "Ubuntu 26.04 is the browser-QA baseline; found ${VERSION_ID:-unknown}" >&2
  exit 2
fi
if [ "${DISPLAY:-}" != ":99" ] || [ ! -S /tmp/.X11-unix/X99 ]; then
  echo "guest-local Xorg :99 is required" >&2
  exit 2
fi
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
  echo "WAYLAND_DISPLAY must be unset; host Wayland access is forbidden" >&2
  exit 2
fi

CARBONYL_ROOT="$(cd "$(dirname -- "$0")/.." && pwd)"
CARBONYL_BIN="$(realpath -- "$CARBONYL_BIN")"
FIXTURE_SOURCE="$CARBONYL_ROOT/tests/fixtures/extensions/mv3-runtime"
TEST_ROOT="$(mktemp -d /tmp/carbonyl-extension-runtime.XXXXXX)"
SERVER_PID=

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  if [ "${KEEP_WORK_DIR:-0}" = 1 ]; then
    echo "Retained extension runtime artifacts: $TEST_ROOT" >&2
  else
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

cp -a -- "$FIXTURE_SOURCE" "$TEST_ROOT/extension"
EXTENSION_PATH="$(realpath -- "$TEST_ROOT/extension")"

python3 - "$TEST_ROOT/port" "$CARBONYL_ROOT/tests/fixtures/extensions" <<'PY' &
import http.server
import pathlib
import socketserver
import sys

port_file = pathlib.Path(sys.argv[1])
root = sys.argv[2]

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, _format, *_args):
        pass

handler = lambda *args, **kwargs: QuietHandler(*args, directory=root, **kwargs)
with socketserver.TCPServer(("127.0.0.1", 0), handler) as server:
    port_file.write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
SERVER_PID=$!

for _attempt in $(seq 1 50); do
  [ -s "$TEST_ROOT/port" ] && break
  sleep 0.1
done
[ -s "$TEST_ROOT/port" ] || { echo "fixture server did not start" >&2; exit 1; }
PORT="$(<"$TEST_ROOT/port")"

run_browser() {
  local profile=$1
  local host=$2
  local output=$3
  local status
  shift 3
  if timeout 30s "$CARBONYL_BIN" \
      --ozone-platform=x11 \
      --disable-gpu \
      --user-data-dir="$profile" \
      --dump-text=dom \
      --virtual-time-budget=5000 \
      "$@" \
      "http://$host:$PORT/runtime-page.html" >"$output" 2>&1; then
    return 0
  else
    status=$?
  fi
  if [ "$status" -ne 1 ]; then
    echo "browser exited with unexpected status $status for $profile" >&2
    exit 1
  fi
  return 1
}

assert_contains() {
  rg -q --fixed-strings -- "$2" "$1" || {
    echo "missing '$2' in $1" >&2
    exit 1
  }
}

assert_not_contains() {
  if rg -q --fixed-strings -- "$2" "$1"; then
    echo "unexpected '$2' in $1" >&2
    exit 1
  fi
}

run_browser "$TEST_ROOT/default-profile" 127.0.0.1 "$TEST_ROOT/default.out"
if rg -q -- 'data-carbonyl-extension-(content|worker|storage|port)' \
    "$TEST_ROOT/default.out"; then
  echo "extension activated without explicit opt-in" >&2
  exit 1
fi

extension_flags=(
  "--load-extension=$EXTENSION_PATH"
  "--disable-extensions-except=$EXTENSION_PATH"
)
run_browser "$TEST_ROOT/persistent-profile" 127.0.0.1 \
  "$TEST_ROOT/first.out" "${extension_flags[@]}"
assert_contains "$TEST_ROOT/first.out" 'data-carbonyl-extension-content="loaded"'
assert_contains "$TEST_ROOT/first.out" 'data-carbonyl-extension-worker="ready"'
assert_contains "$TEST_ROOT/first.out" 'data-carbonyl-extension-port="ready"'
assert_contains "$TEST_ROOT/first.out" 'data-carbonyl-extension-storage="1"'
assert_contains "$TEST_ROOT/first.out" 'data-carbonyl-dnr="blocked"'
assert_contains "$TEST_ROOT/first.out" 'CARBONYL_EXTENSION_DIAGNOSTIC state=loaded'
FIRST_EXTENSION_ID="$(rg -o ' id=[a-p]{32}' "$TEST_ROOT/first.out" | head -1)"
[ -n "$FIRST_EXTENSION_ID" ] || {
  echo "extension diagnostic did not contain a stable ID" >&2
  exit 1
}
EXTENSION_ID=${FIRST_EXTENSION_ID# id=}

run_browser "$TEST_ROOT/persistent-profile" 127.0.0.1 \
  "$TEST_ROOT/restart.out" "${extension_flags[@]}"
assert_contains "$TEST_ROOT/restart.out" 'data-carbonyl-extension-storage="2"'
assert_contains "$TEST_ROOT/restart.out" "$FIRST_EXTENSION_ID"

run_browser "$TEST_ROOT/persistent-profile" 127.0.0.1 \
  "$TEST_ROOT/disable-request.out" "${extension_flags[@]}" \
  "--carbonyl-extension-management=restart" \
  "--carbonyl-extension-list" \
  "--carbonyl-extension-mutation=disable:$EXTENSION_ID"
assert_contains "$TEST_ROOT/disable-request.out" \
  'operation=disable id='"$EXTENSION_ID"' result=restart_required'

run_browser "$TEST_ROOT/persistent-profile" 127.0.0.1 \
  "$TEST_ROOT/disabled.out" "${extension_flags[@]}" \
  "--carbonyl-extension-management=read-only" \
  "--carbonyl-extension-list"
assert_contains "$TEST_ROOT/disabled.out" 'state=disabled_restart'
if rg -q -- 'data-carbonyl-extension-content' "$TEST_ROOT/disabled.out"; then
  echo "restart-disabled extension unexpectedly executed" >&2
  exit 1
fi

run_browser "$TEST_ROOT/persistent-profile" 127.0.0.1 \
  "$TEST_ROOT/enable-request.out" "${extension_flags[@]}" \
  "--carbonyl-extension-management=restart" \
  "--carbonyl-extension-mutation=enable:$EXTENSION_ID"
assert_contains "$TEST_ROOT/enable-request.out" \
  'operation=enable id='"$EXTENSION_ID"' result=restart_required'

run_browser "$TEST_ROOT/persistent-profile" 127.0.0.1 \
  "$TEST_ROOT/re-enabled.out" "${extension_flags[@]}" \
  "--carbonyl-extension-management=read-only" \
  "--carbonyl-extension-list"
assert_contains "$TEST_ROOT/re-enabled.out" 'data-carbonyl-extension-storage="4"'
assert_contains "$TEST_ROOT/re-enabled.out" 'CARBONYL_EXTENSION_STATUS state=loaded'

run_browser "$TEST_ROOT/persistent-profile" 127.0.0.1 \
  "$TEST_ROOT/remove-request.out" "${extension_flags[@]}" \
  "--carbonyl-extension-management=restart" \
  "--carbonyl-extension-mutation=remove:$EXTENSION_ID"
assert_contains "$TEST_ROOT/remove-request.out" \
  'operation=remove id='"$EXTENSION_ID"' result=restart_required'

run_browser "$TEST_ROOT/persistent-profile" 127.0.0.1 \
  "$TEST_ROOT/removed.out" "${extension_flags[@]}" \
  "--carbonyl-extension-management=read-only" \
  "--carbonyl-extension-list"
assert_contains "$TEST_ROOT/removed.out" 'state=removed_restart'
if rg -q -- 'data-carbonyl-extension-content' "$TEST_ROOT/removed.out"; then
  echo "restart-removed extension unexpectedly executed" >&2
  exit 1
fi

if run_browser "$TEST_ROOT/policy-denied-profile" 127.0.0.1 \
    "$TEST_ROOT/policy-denied.out" "${extension_flags[@]}" \
    "--carbonyl-extension-management=read-only" \
    "--carbonyl-extension-mutation=disable:$EXTENSION_ID"; then
  echo "read-only daemon policy unexpectedly accepted mutation" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/policy-denied.out" 'management_read_only'

run_browser "$TEST_ROOT/isolated-profile" 127.0.0.1 \
  "$TEST_ROOT/isolated.out" "${extension_flags[@]}"
assert_contains "$TEST_ROOT/isolated.out" 'data-carbonyl-extension-storage="1"'
assert_contains "$TEST_ROOT/isolated.out" "$FIRST_EXTENSION_ID"

run_browser "$TEST_ROOT/permission-profile" localhost \
  "$TEST_ROOT/permission.out" "${extension_flags[@]}"
if rg -q -- 'data-carbonyl-extension-content' "$TEST_ROOT/permission.out"; then
  echo "content script escaped its declared host permission" >&2
  exit 1
fi

if run_browser "$TEST_ROOT/mismatch-profile" 127.0.0.1 \
    "$TEST_ROOT/mismatch.out" "--load-extension=$EXTENSION_PATH"; then
  echo "unpaired extension opt-in unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/mismatch.out" 'code=allowlist_mismatch'

DUPLICATE_PATHS="$EXTENSION_PATH,$EXTENSION_PATH"
if run_browser "$TEST_ROOT/duplicate-profile" 127.0.0.1 \
    "$TEST_ROOT/duplicate.out" \
    "--load-extension=$DUPLICATE_PATHS" \
    "--disable-extensions-except=$DUPLICATE_PATHS"; then
  echo "duplicate extension path unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/duplicate.out" 'code=duplicate_path'

NONCANONICAL_EXTENSION="$TEST_ROOT/extension/../extension"
if run_browser "$TEST_ROOT/noncanonical-profile" 127.0.0.1 \
    "$TEST_ROOT/noncanonical.out" \
    "--load-extension=$NONCANONICAL_EXTENSION" \
    "--disable-extensions-except=$NONCANONICAL_EXTENSION"; then
  echo "noncanonical extension path unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/noncanonical.out" 'code=path_not_canonical'

MISSING_EXTENSION="$TEST_ROOT/missing-extension"
if run_browser "$TEST_ROOT/missing-profile" 127.0.0.1 \
    "$TEST_ROOT/missing.out" \
    "--load-extension=$MISSING_EXTENSION" \
    "--disable-extensions-except=$MISSING_EXTENSION"; then
  echo "missing extension path unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/missing.out" 'code=path_not_canonical'
assert_contains "$TEST_ROOT/missing.out" \
  'CARBONYL_EXTENSION_STATUS state=error'
assert_not_contains "$TEST_ROOT/missing.out" "$MISSING_EXTENSION"

cp -a -- "$FIXTURE_SOURCE" "$TEST_ROOT/symlink-extension"
ln -s -- /etc/hosts "$TEST_ROOT/symlink-extension/escape"
SYMLINK_EXTENSION="$(realpath -- "$TEST_ROOT/symlink-extension")"
if run_browser "$TEST_ROOT/symlink-profile" 127.0.0.1 \
    "$TEST_ROOT/symlink.out" \
    "--load-extension=$SYMLINK_EXTENSION" \
    "--disable-extensions-except=$SYMLINK_EXTENSION"; then
  echo "symlink-bearing extension unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/symlink.out" 'code=symlink_rejected'

cp -a -- "$FIXTURE_SOURCE" "$TEST_ROOT/malformed-extension"
printf '%s\n' '{"manifest_version":3' > \
  "$TEST_ROOT/malformed-extension/manifest.json"
MALFORMED_EXTENSION="$(realpath -- "$TEST_ROOT/malformed-extension")"
if run_browser "$TEST_ROOT/malformed-profile" 127.0.0.1 \
    "$TEST_ROOT/malformed.out" \
    "--load-extension=$MALFORMED_EXTENSION" \
    "--disable-extensions-except=$MALFORMED_EXTENSION"; then
  echo "malformed manifest unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/malformed.out" 'code=invalid_manifest'
assert_contains "$TEST_ROOT/malformed.out" \
  'CARBONYL_EXTENSION_STATUS state=error'
assert_not_contains "$TEST_ROOT/malformed.out" "$MALFORMED_EXTENSION"

cp -a -- "$FIXTURE_SOURCE" "$TEST_ROOT/unsupported-extension"
sed -i 's/"manifest_version": 3/"manifest_version": 2/' \
  "$TEST_ROOT/unsupported-extension/manifest.json"
UNSUPPORTED_EXTENSION="$(realpath -- "$TEST_ROOT/unsupported-extension")"
if run_browser "$TEST_ROOT/unsupported-profile" 127.0.0.1 \
    "$TEST_ROOT/unsupported.out" \
    "--load-extension=$UNSUPPORTED_EXTENSION" \
    "--disable-extensions-except=$UNSUPPORTED_EXTENSION"; then
  echo "unsupported manifest unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/unsupported.out" 'code=unsupported_manifest'

cp -a -- "$FIXTURE_SOURCE" "$TEST_ROOT/privileged-extension"
sed -i 's/"storage"/"storage",\n    "tabs"/' \
  "$TEST_ROOT/privileged-extension/manifest.json"
PRIVILEGED_EXTENSION="$(realpath -- "$TEST_ROOT/privileged-extension")"
if run_browser "$TEST_ROOT/privileged-profile" 127.0.0.1 \
    "$TEST_ROOT/privileged.out" \
    "--load-extension=$PRIVILEGED_EXTENSION" \
    "--disable-extensions-except=$PRIVILEGED_EXTENSION"; then
  echo "unsupported privileged permission unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/privileged.out" 'code=unsupported_permission'

cp -a -- "$FIXTURE_SOURCE" "$TEST_ROOT/file-host-extension"
sed -i 's#http://127\.0\.0\.1/\*#file:///*#g' \
  "$TEST_ROOT/file-host-extension/manifest.json"
FILE_HOST_EXTENSION="$(realpath -- "$TEST_ROOT/file-host-extension")"
if run_browser "$TEST_ROOT/file-host-profile" 127.0.0.1 \
    "$TEST_ROOT/file-host.out" \
    "--load-extension=$FILE_HOST_EXTENSION" \
    "--disable-extensions-except=$FILE_HOST_EXTENSION"; then
  echo "non-HTTP host permission unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/file-host.out" 'code=unsupported_host_scheme'

cp -a -- "$FIXTURE_SOURCE" "$TEST_ROOT/remote-update-extension"
sed -i \
  's/"name": "Carbonyl MV3 Runtime Fixture"/"name": "Carbonyl MV3 Runtime Fixture",\n  "update_url": "https:\/\/example.invalid\/update.xml"/' \
  "$TEST_ROOT/remote-update-extension/manifest.json"
REMOTE_UPDATE_EXTENSION="$(realpath -- "$TEST_ROOT/remote-update-extension")"
if run_browser "$TEST_ROOT/remote-update-profile" 127.0.0.1 \
    "$TEST_ROOT/remote-update.out" \
    "--load-extension=$REMOTE_UPDATE_EXTENSION" \
    "--disable-extensions-except=$REMOTE_UPDATE_EXTENSION"; then
  echo "remote update manifest unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/remote-update.out" 'code=remote_update_forbidden'

cp -a -- "$FIXTURE_SOURCE" "$TEST_ROOT/invalid-dnr-extension"
printf '%s\n' '[{"id": 0}]' > \
  "$TEST_ROOT/invalid-dnr-extension/rules.json"
INVALID_DNR_EXTENSION="$(realpath -- "$TEST_ROOT/invalid-dnr-extension")"
if run_browser "$TEST_ROOT/invalid-dnr-profile" 127.0.0.1 \
    "$TEST_ROOT/invalid-dnr.out" \
    "--load-extension=$INVALID_DNR_EXTENSION" \
    "--disable-extensions-except=$INVALID_DNR_EXTENSION"; then
  echo "invalid DNR ruleset unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$TEST_ROOT/invalid-dnr.out" 'code=invalid_dnr_ruleset'

echo "PASS: Ubuntu 26.04 isolated-Xorg unpacked MV3 runtime integration"
