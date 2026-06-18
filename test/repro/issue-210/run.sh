#!/usr/bin/env bash
# Reproduction harness for issue #210 (upstream fathyb#181):
# "blank after ~1s in a docker container".
#
# Builds a clean GPU-less debian image, runs the prebuilt carbonyl binary
# against a page inside it, and replays the captured ANSI stream through a
# terminal emulator to decide blank-vs-content (see analyze.py).
#
# Usage:
#   ./run.sh <prebuilt-dir> [url] [extra-carbonyl-flags...]
#
# Example:
#   ./run.sh ../../../build/pre-built/x86_64-unknown-linux-gnu \
#            https://en.wikipedia.org/wiki/Chromium_(web_browser)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${1:?usage: run.sh <prebuilt-dir> [url] [flags...]}"
URL="${2:-https://en.wikipedia.org/wiki/Chromium_(web_browser)}"
shift || true; shift || true
FLAGS="$*"
IMAGE="carbonyl-repro:bullseye"
RAW="$(mktemp /tmp/cb-210-XXXX.bin)"

echo "==> building $IMAGE"
docker build -t "$IMAGE" "$HERE" >/dev/null

echo "==> probing: url=$URL flags='${FLAGS:-<none>}'"
python3 "$HERE/probe.py" --bin-dir "$BIN_DIR" --url "$URL" --flags "$FLAGS" --image "$IMAGE" --out "$RAW"

echo "==> analyzing final screen"
python3 "$HERE/analyze.py" "$RAW"   # exit 0 = content rendered, 1 = blank reproduced
rc=$?
rm -f "$RAW"
exit $rc
