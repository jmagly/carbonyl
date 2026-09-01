#!/usr/bin/env bash
# Standalone policy coverage for the Carbonyl-owned operator controls (#288).

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")"
: "${CXX:=c++}"
command -v "$CXX" >/dev/null 2>&1 || {
    echo "FAIL: C++ compiler not found: $CXX"; exit 1; }

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/carbonyl-controls-model.XXXXXX")"
cleanup() { rm -rf -- "$WORK_DIR"; }
trap cleanup EXIT

ln -s "$CARBONYL_ROOT" "$WORK_DIR/carbonyl"
"$CXX" -std=c++20 -Wall -Wextra -Werror -pedantic \
    -I "$WORK_DIR" \
    "$CARBONYL_ROOT/src/browser/operator_controls_model.cc" \
    "$CARBONYL_ROOT/src/browser/operator_controls_model_unittest.cc" \
    -o "$WORK_DIR/operator-controls-model-test"
"$WORK_DIR/operator-controls-model-test"
