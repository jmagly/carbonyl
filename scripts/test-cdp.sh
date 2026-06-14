#!/usr/bin/env bash
# test-cdp.sh - Verify Carbonyl exposes CDP while terminal rendering continues.

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")"
cd "$CARBONYL_ROOT"

if [ -z "${CARBONYL_BIN:-}" ]; then
    triple="$(scripts/platform-triple.sh)"
    CARBONYL_BIN="build/pre-built/$triple/carbonyl"
    export LD_LIBRARY_PATH="build/pre-built/$triple${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

[ -x "$CARBONYL_BIN" ] || { echo "FAIL: carbonyl binary not found at $CARBONYL_BIN"; exit 1; }

for cmd in curl node script; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: $cmd not on PATH"; exit 1; }
done

PORT="${CARBONYL_CDP_PORT:-9333}"
HOST="${CARBONYL_CDP_HOST:-127.0.0.1}"
CAPTURE_SECONDS="${CAPTURE_SECONDS:-3}"
TMPDIR_BASE="${TMPDIR:-/tmp}"
FIXTURE="$CARBONYL_ROOT/tests/fixtures/x-mirror.html"
[ -f "$FIXTURE" ] || { echo "FAIL: fixture missing: $FIXTURE"; exit 1; }

WORK_DIR="$(mktemp -d "$TMPDIR_BASE/carbonyl-cdp-test.XXXXXX")"
TERM_LOG="$WORK_DIR/terminal.log"
SCRIPT_OUT="$WORK_DIR/script.out"
SCRIPT_ERR="$WORK_DIR/script.err"

cleanup() {
    [ -n "${CARBONYL_PID:-}" ] && kill "$CARBONYL_PID" 2>/dev/null || true
    [ -n "${CARBONYL_PID:-}" ] && wait "$CARBONYL_PID" 2>/dev/null || true
    [ -n "${WORK_DIR:-}" ] && [ -z "${KEEP_WORK_DIR:-}" ] && rm -rf "$WORK_DIR" || true
}
trap cleanup EXIT

echo "==> Launching Carbonyl with CDP"
echo "    bin=$CARBONYL_BIN"
echo "    cdp=http://$HOST:$PORT"
echo "    fixture=file://$FIXTURE"
echo "    work_dir=$WORK_DIR"

CARBONYL_CMD=(
    "$CARBONYL_BIN"
    --no-sandbox
    --remote-debugging-address="$HOST"
    --remote-debugging-port="$PORT"
    --viewport=1280x720
    "file://$FIXTURE"
)
printf -v CARBONYL_CMD_QUOTED '%q ' "${CARBONYL_CMD[@]}"
COLORTERM=truecolor \
TERM="${TERM:-xterm-256color}" \
    script -q -c "$CARBONYL_CMD_QUOTED" "$TERM_LOG" >"$SCRIPT_OUT" 2>"$SCRIPT_ERR" &
CARBONYL_PID=$!

echo "==> Waiting for DevTools endpoint"
for _ in $(seq 1 40); do
    if curl --silent --fail "http://$HOST:$PORT/json/version" >"$WORK_DIR/version.json"; then
        break
    fi
    sleep 0.5
done
curl --silent --fail "http://$HOST:$PORT/json/version"

echo
echo "==> Exercising CDP domains"
node - "$HOST" "$PORT" "file://$FIXTURE" <<'NODE'
const [host, port, fixtureUrl] = process.argv.slice(2);

const list = await fetch(`http://${host}:${port}/json/list`).then((response) => response.json());
if (!Array.isArray(list) || list.length === 0) {
  throw new Error('no CDP targets returned by /json/list');
}

const target = list.find((entry) => entry.type === 'page') || list[0];
if (!target.webSocketDebuggerUrl) {
  throw new Error('target is missing webSocketDebuggerUrl');
}

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  ws.addEventListener('open', resolve, { once: true });
  ws.addEventListener('error', reject, { once: true });
});

let id = 0;
const pending = new Map();
ws.addEventListener('message', (event) => {
  const message = JSON.parse(event.data);
  if (!message.id || !pending.has(message.id)) {
    return;
  }
  const { method, resolve, reject } = pending.get(message.id);
  pending.delete(message.id);
  if (message.error) {
    reject(new Error(`${method}: ${JSON.stringify(message.error)}`));
  } else {
    resolve(message.result);
  }
});

function send(method, params = {}) {
  const message = { id: ++id, method, params };
  ws.send(JSON.stringify(message));
  return new Promise((resolve, reject) => {
    pending.set(message.id, { method, resolve, reject });
    setTimeout(() => reject(new Error(`${method}: timeout`)), 5000).unref();
  });
}

await send('Runtime.enable');
await send('Page.enable');
await send('Network.enable');
await send('Page.navigate', { url: fixtureUrl });

for (let attempt = 0; attempt < 20; attempt += 1) {
  const state = await send('Runtime.evaluate', {
    expression: 'document.readyState',
    returnByValue: true,
  });
  if (state.result?.value === 'complete') {
    break;
  }
  await new Promise((resolve) => setTimeout(resolve, 250));
}

const title = await send('Runtime.evaluate', {
  expression: 'document.title',
  returnByValue: true,
});
const dom = await send('DOM.getDocument', { depth: 1 });
const ax = await send('Accessibility.getFullAXTree');
const screenshot = await send('Page.captureScreenshot', { format: 'png' });

if (title.result?.value !== 'Carbonyl X-mirror dual-output test') {
  throw new Error(`unexpected title: ${title.result?.value}`);
}
if (dom.root?.nodeName !== '#document') {
  throw new Error('DOM.getDocument did not return a document root');
}
if (!Array.isArray(ax.nodes) || ax.nodes.length === 0) {
  throw new Error('Accessibility.getFullAXTree returned no nodes');
}
if (!screenshot.data || screenshot.data.length < 1000) {
  throw new Error('Page.captureScreenshot returned an unexpectedly small image');
}

ws.close();
console.log(JSON.stringify({
  target: target.url,
  title: title.result.value,
  axNodes: ax.nodes.length,
  screenshotBytesBase64: screenshot.data.length,
}, null, 2));
NODE

sleep "$CAPTURE_SECONDS"
kill "$CARBONYL_PID" 2>/dev/null || true
wait "$CARBONYL_PID" 2>/dev/null || true
unset CARBONYL_PID

echo "==> Checking terminal rendering"
terminal_bytes="$(wc -c < "$TERM_LOG")"
echo "    terminal_log_bytes=$terminal_bytes"

if [ "$terminal_bytes" -lt 1000 ]; then
    echo "FAIL: terminal log is too small; rendering likely did not start"
    [ -n "${KEEP_WORK_DIR:-}" ] && echo "artefacts kept at $WORK_DIR"
    exit 1
fi

if ! grep -aq "CARBONYL_X_MIRROR_TEST_MARKER" "$TERM_LOG"; then
    echo "FAIL: terminal log did not contain fixture marker"
    [ -n "${KEEP_WORK_DIR:-}" ] && echo "artefacts kept at $WORK_DIR"
    exit 1
fi

if ! grep -aq "\\[48;2;" "$TERM_LOG"; then
    echo "FAIL: terminal log did not contain truecolor background SGR"
    [ -n "${KEEP_WORK_DIR:-}" ] && echo "artefacts kept at $WORK_DIR"
    exit 1
fi

echo
echo "PASS - CDP endpoint and terminal rendering are both active."
