#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname -- "$0")/../../.." && pwd)"
cd "$ROOT"

BIN="${CARBONYL_BIN:-build/pre-built/x86_64-unknown-linux-gnu/carbonyl}"
LIB_DIR="$(dirname "$BIN")"
OUT_DIR="${OUT_DIR:-.aiwg/measurements/issue-241}"
VIEWPORT="${VIEWPORT:-1280x800}"
IDLE_MS="${IDLE_MS:-150}"
MAX_WAIT_MS="${MAX_WAIT_MS:-15000}"
URL="${1:-file://$ROOT/test/repro/issue-241/fixture.html}"

mkdir -p "$OUT_DIR"

run_dump() {
    local format="$1"
    local stem="$2"
    local output="$OUT_DIR/${stem}.${format}"
    local log="$OUT_DIR/${stem}.${format}.log"

    LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        "$BIN" \
        --debug \
        --no-sandbox \
        "--dump=$format" \
        "--viewport=$VIEWPORT" \
        "--idle=$IDLE_MS" \
        "--max-wait=$MAX_WAIT_MS" \
        "$URL" >"$output" 2>"$log"

    printf "%s payload_bytes=%s log=%s\n" \
        "$format" \
        "$(wc -c <"$output")" \
        "$log"
    grep -E "dump-frame .* stats:" "$log" | tail -1 || true
}

stem="$(basename "${URL#file://}")"
stem="${stem%.*}-${VIEWPORT}"
stem="${stem//[^A-Za-z0-9_.-]/_}"

run_dump sixel "$stem"
run_dump kitty "$stem"
run_dump iterm2 "$stem"
