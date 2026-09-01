#!/usr/bin/env bash
# Non-display contract test for the dedicated operator-shell launcher (#286).

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/carbonyl-operator-launcher.XXXXXX")"

cleanup() {
    rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR/include/carbonyl" "$WORK_DIR/working" \
    "$WORK_DIR/missing-sibling"
ln -s "$CARBONYL_ROOT/src" "$WORK_DIR/include/carbonyl/src"

cat > "$WORK_DIR/working/headless_shell" <<'FAKE_SHELL'
#!/usr/bin/env bash
set -euo pipefail
: "${OPERATOR_CAPTURE_FILE:?}"
printf '%s\n' "$@" > "$OPERATOR_CAPTURE_FILE"
FAKE_SHELL
chmod +x "$WORK_DIR/working/headless_shell"

CXX_BIN="${CXX:-c++}"
COMMON_SOURCES=(
    "$CARBONYL_ROOT/src/browser/operator_shell_command_line.cc"
)
COMMON_FLAGS=(
    -std=c++20
    -Wall
    -Wextra
    -Werror
    "-I$WORK_DIR/include"
)

"$CXX_BIN" "${COMMON_FLAGS[@]}" "${COMMON_SOURCES[@]}" \
    "$CARBONYL_ROOT/src/browser/operator_shell_command_line_unittest.cc" \
    -o "$WORK_DIR/operator_shell_command_line_unittests"
"$WORK_DIR/operator_shell_command_line_unittests"

"$CXX_BIN" "${COMMON_FLAGS[@]}" "${COMMON_SOURCES[@]}" \
    "$CARBONYL_ROOT/src/browser/operator_shell_main.cc" \
    -o "$WORK_DIR/working/carbonyl_operator_shell"

CAPTURE="$WORK_DIR/arguments.txt"
OPERATOR_CAPTURE_FILE="$CAPTURE" \
    "$WORK_DIR/working/carbonyl_operator_shell" \
    --user-data-dir=/tmp/profile https://example.com
ACTUAL="$(sed -n '1,10p' "$CAPTURE")"
EXPECTED=$'--carbonyl-operator-window\n--user-data-dir=/tmp/profile\nhttps://example.com'
[ "$ACTUAL" = "$EXPECTED" ] || {
    printf 'FAIL: launcher argument order\n%s\n' "$ACTUAL" >&2
    exit 1
}

OPERATOR_CAPTURE_FILE="$CAPTURE" \
    "$WORK_DIR/working/carbonyl_operator_shell" \
    --carbonyl-operator-window https://example.com
[ "$(grep -c '^--carbonyl-operator-window$' "$CAPTURE")" -eq 1 ] || {
    echo 'FAIL: launcher duplicated the operator switch' >&2
    exit 1
}

cp "$WORK_DIR/working/carbonyl_operator_shell" \
    "$WORK_DIR/missing-sibling/carbonyl_operator_shell"
set +e
MISSING_OUTPUT="$(
    "$WORK_DIR/missing-sibling/carbonyl_operator_shell" \
        https://example.com 2>&1
)"
MISSING_RC=$?
set -e
[ "$MISSING_RC" -eq 127 ]
grep -Eq 'cannot execute .*/headless_shell:' <<< "$MISSING_OUTPUT"

echo 'PASS: dedicated operator-shell launcher contract'
