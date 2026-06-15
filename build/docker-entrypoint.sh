#!/bin/sh
# Container entrypoint for the Carbonyl runtime image (#132, ADR-004).
#
# Sets container-safe terminal env, normalizes the --zoom flag, and execs the
# installed /usr/bin/carbonyl launcher (from the .deb) under tini. The terminal
# env, dbus-disable, shell-mode, and zoom-normalization approach is adapted from
# the community PR jmagly/carbonyl#1 by @eSlider; re-pointed at the .deb launcher.

set -eu

export TERM="${TERM:-xterm-256color}"
export LANG="${LANG:-C.UTF-8}"
export COLORTERM="${COLORTERM:-truecolor}"

# Containers usually have no system dbus; silence connection spam on stderr.
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-disabled:}"

# Skip the Rust PTY re-exec wrapper; we already run under tini in a container.
export CARBONYL_ENV_SHELL_MODE="${CARBONYL_ENV_SHELL_MODE:-1}"

# Release runtimes through ~alpha.9 apply an internal 1.5x zoom (pre-#100), so a
# default --zoom=67 yields ~100% effective zoom. Carbonyl accepts only the equals
# form (--zoom=N / -z=N); normalize space-separated "-z 50" / "--zoom 50" here so
# the value isn't mistaken for a URL. Set CARBONYL_ZOOM=100 once runtimes ship
# without the 1.5x multiplier.
ZOOM_PERCENT=""
ARGS_FILE="$(mktemp)"
trap 'rm -f "$ARGS_FILE"' EXIT INT TERM
: > "$ARGS_FILE"

while [ $# -gt 0 ]; do
  case "$1" in
    -z|--zoom)
      shift
      [ $# -gt 0 ] || { echo "carbonyl: --zoom requires a value (use --zoom=50 or -z 50)" >&2; exit 2; }
      ZOOM_PERCENT="$1"; shift ;;
    -z=*|--zoom=*)
      ZOOM_PERCENT="${1#*=}"; shift ;;
    *)
      printf '%s\n' "$1" >> "$ARGS_FILE"; shift ;;
  esac
done

[ -n "$ZOOM_PERCENT" ] || ZOOM_PERCENT="${CARBONYL_ZOOM:-67}"

set --
while IFS= read -r arg; do
  [ -n "$arg" ] || continue
  set -- "$@" "$arg"
done < "$ARGS_FILE"

exec /usr/bin/carbonyl \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --user-data-dir="${CARBONYL_DATA_DIR:-/home/carbonyl/profile}" \
  --zoom="${ZOOM_PERCENT}" \
  "$@"
