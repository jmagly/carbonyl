#!/usr/bin/env bash
# smoke-packages.sh — render-smoke the built Linux packages (#138).
#
# For each package format, install it into a clean container that matches the
# format's target distro, then render a real page with `carbonyl --dump-text`
# and assert the page text appears AND no runtime library is missing AND
# fontconfig produced zero errors. A package whose declared/bundled dependency
# set is incomplete fails here — in CI — instead of at the user's terminal.
#
#   deb      → ubuntu:24.04        (apt resolves the .deb's Depends)
#   rpm      → fedora:latest       (dnf resolves the .rpm's Requires)
#   appimage → ubuntu:24.04 BARE   (only ca-certificates; proves self-contained)
#
# The AppImage container is deliberately bare: an AppImage that relies on host
# libraries passes the deb/rpm checks but fails here, which is the point.
#
# Usage:
#   bash scripts/smoke-packages.sh [--deb FILE] [--rpm FILE] [--appimage FILE]
#        [--url URL] [--expect TEXT] [--keep]
#
# At least one of --deb/--rpm/--appimage is required. Exit non-zero if any
# provided format fails its render smoke. Requires docker.

set -euo pipefail

deb="" rpm="" appimage=""
url="https://example.com"
expect="Example Domain"
keep=0

usage() { sed -n '2,28p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --deb) deb="$2"; shift 2 ;;
    --deb=*) deb="${1#--deb=}"; shift ;;
    --rpm) rpm="$2"; shift 2 ;;
    --rpm=*) rpm="${1#--rpm=}"; shift ;;
    --appimage) appimage="$2"; shift 2 ;;
    --appimage=*) appimage="${1#--appimage=}"; shift ;;
    --url) url="$2"; shift 2 ;;
    --url=*) url="${1#--url=}"; shift ;;
    --expect) expect="$2"; shift 2 ;;
    --expect=*) expect="${1#--expect=}"; shift ;;
    --keep) keep=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$deb$rpm$appimage" ] || { echo "ERROR: provide at least one of --deb/--rpm/--appimage" >&2; usage >&2; exit 2; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is required" >&2; exit 1; }

# Render flags: idle/max-wait give the page time to paint; --no-sandbox because
# the container has no user-namespace sandbox (and the smoke runs as root).
RENDER="carbonyl --no-sandbox --disable-dev-shm-usage --disable-gpu \
  --dump-text --idle=4000 --max-wait=25000 $url"

fail=0
results=""

# assert <label> <combined-output-file> — PASS iff expected text present, no
# missing shared library, and zero fontconfig errors.
assert() {
  local label="$1" outf="$2" ok=1 reason=""
  grep -qF "$expect" "$outf"            || { ok=0; reason="missing expected text '$expect'"; }
  if grep -q "error while loading shared libraries" "$outf"; then
    ok=0; reason="missing shared library: $(grep -m1 'error while loading shared libraries' "$outf" | sed 's/.*: //')"
  fi
  local fcerr; fcerr="$(grep -c -i 'fontconfig error' "$outf" || true)"
  [ "${fcerr:-0}" -eq 0 ]               || { ok=0; reason="${fcerr} fontconfig error(s)"; }
  if [ "$ok" -eq 1 ]; then
    echo "  [OK] $label — rendered '$expect', no missing libs, 0 fontconfig errors"
    results="${results}  [OK] ${label}\n"
  else
    echo "  [XX] $label — $reason"
    echo "  ---- captured output (tail) ----"
    tail -25 "$outf" | sed 's/^/      /'
    results="${results}  [XX] ${label} — ${reason}\n"
    fail=1
  fi
}

work="$(mktemp -d)"
# shellcheck disable=SC2317  # invoked indirectly via trap
cleanup() { [ "$keep" -eq 1 ] || rm -rf "$work"; }
trap cleanup EXIT

if [ -n "$deb" ]; then
  echo "=== deb render smoke (ubuntu:24.04) — $(basename "$deb") ==="
  cp "$deb" "$work/pkg.deb"
  docker run --rm -v "$work/pkg.deb:/pkg.deb:ro" ubuntu:24.04 sh -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends /pkg.deb ca-certificates >/dev/null
    '"$RENDER"' 2>&1
  ' >"$work/deb.out" 2>&1 || true
  assert "deb" "$work/deb.out"
fi

if [ -n "$rpm" ]; then
  echo "=== rpm render smoke (fedora:latest) — $(basename "$rpm") ==="
  cp "$rpm" "$work/pkg.rpm"
  docker run --rm -v "$work/pkg.rpm:/pkg.rpm:ro" fedora:latest sh -c '
    set -e
    dnf install -y -q /pkg.rpm ca-certificates >/dev/null 2>&1
    '"$RENDER"' 2>&1
  ' >"$work/rpm.out" 2>&1 || true
  assert "rpm" "$work/rpm.out"
fi

if [ -n "$appimage" ]; then
  echo "=== appimage render smoke (BARE ubuntu:24.04 — only ca-certificates) — $(basename "$appimage") ==="
  cp "$appimage" "$work/app.AppImage"
  chmod +x "$work/app.AppImage"
  # No FUSE in CI containers → --appimage-extract-and-run. The container gets
  # ONLY ca-certificates (TLS roots) + libfuse2 is NOT installed; nothing else.
  docker run --rm -v "$work/app.AppImage:/app.AppImage:ro" ubuntu:24.04 sh -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends ca-certificates >/dev/null
    cp /app.AppImage /tmp/app.AppImage && chmod +x /tmp/app.AppImage
    APPIMAGE_BIN=/tmp/app.AppImage
    "$APPIMAGE_BIN" --appimage-extract-and-run --no-sandbox --disable-dev-shm-usage \
      --disable-gpu --dump-text --idle=4000 --max-wait=25000 '"$url"' 2>&1
  ' >"$work/appimage.out" 2>&1 || true
  assert "appimage" "$work/appimage.out"
fi

echo
echo "=== package render smoke summary ==="
printf '%b' "$results"
[ "$fail" -eq 0 ] && echo "All package render smokes passed." || echo "One or more package render smokes FAILED."
exit "$fail"
