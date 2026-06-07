#!/bin/sh
set -eu

export TERM="${TERM:-xterm-256color}"
export LANG="${LANG:-C.UTF-8}"
export COLORTERM="${COLORTERM:-truecolor}"
export LD_LIBRARY_PATH="/carbonyl${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Containers usually have no system dbus; avoid connect spam on stderr.
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-disabled:}"

exec /carbonyl/carbonyl \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --user-data-dir=/carbonyl/data \
  "$@"
