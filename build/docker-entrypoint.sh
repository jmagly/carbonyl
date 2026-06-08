#!/bin/sh
set -eu

export TERM="${TERM:-xterm-256color}"
export LANG="${LANG:-C.UTF-8}"
export COLORTERM="${COLORTERM:-truecolor}"
export LD_LIBRARY_PATH="/carbonyl${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Containers usually have no system dbus; avoid connect spam on stderr.
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-disabled:}"

# Skip the Rust PTY re-exec wrapper; we already run in a container with tini.
export CARBONYL_ENV_SHELL_MODE="${CARBONYL_ENV_SHELL_MODE:-1}"

# Release runtimes through v0.2.0-alpha.8 apply an internal 1.5× zoom multiplier
# (see src/output/window.rs before #100). Compensate so Docker matches ~100% zoom.
# Carbonyl only accepts --zoom=N / -z=N (equals form). Space-separated "-z 50" is
# not parsed and "50" becomes a bogus URL — normalize here before exec.
ZOOM_PERCENT=""
USER_ARGS_FILE=$(mktemp)
trap 'rm -f "$USER_ARGS_FILE"' EXIT INT TERM
: > "$USER_ARGS_FILE"

while [ $# -gt 0 ]; do
  case "$1" in
    -z|--zoom)
      shift
      if [ $# -eq 0 ]; then
        echo "carbonyl: --zoom requires a value (use --zoom=50 or -z 50)" >&2
        exit 2
      fi
      ZOOM_PERCENT="$1"
      shift
      ;;
    -z=*|--zoom=*)
      ZOOM_PERCENT="${1#*=}"
      shift
      ;;
    *)
      printf '%s\n' "$1" >> "$USER_ARGS_FILE"
      shift
      ;;
  esac
done

if [ -z "$ZOOM_PERCENT" ]; then
  ZOOM_PERCENT="${CARBONYL_ZOOM:-67}"
fi

set --
while IFS= read -r arg; do
  [ -n "$arg" ] || continue
  set -- "$@" "$arg"
done < "$USER_ARGS_FILE"

exec /carbonyl/carbonyl \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --user-data-dir=/carbonyl/data \
  --zoom="${ZOOM_PERCENT}" \
  "$@"
