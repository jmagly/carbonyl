#!/bin/sh
set -eu

export TERM="${TERM:-xterm-256color}"
export LANG="${LANG:-C.UTF-8}"
export COLORTERM="${COLORTERM:-truecolor}"
export LD_LIBRARY_PATH="/carbonyl${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Containers usually have no system dbus; avoid connect spam on stderr.
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-disabled:}"

# Release runtimes through v0.2.0-alpha.8 apply an internal 1.5× zoom multiplier
# (see src/output/window.rs before #100). Compensate so Docker matches a normal
# 100% zoom. Override with CARBONYL_ZOOM=100 when tarballs ship without it, or
# pass --zoom= on the docker run command line (user args win).
ZOOM_PERCENT="${CARBONYL_ZOOM:-67}"

exec /carbonyl/carbonyl \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --user-data-dir=/carbonyl/data \
  --zoom="${ZOOM_PERCENT}" \
  "$@"
