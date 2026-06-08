#!/usr/bin/env bash
# docker-runtime-context.sh — Download a release tarball and prepare build/carbonyl-runtime/
#
# Mirrors the asset download + verify steps in .github/workflows/docker.yml.
#
# Usage:
#   scripts/docker-runtime-context.sh 0.2.0-alpha.8              # headless
#   scripts/docker-runtime-context.sh 0.2.0-alpha.8 x11          # x11 ozone variant
#   RELEASE_REPO=jmagly/carbonyl scripts/docker-runtime-context.sh 0.2.0-alpha.8

set -euo pipefail

VERSION="${1:?usage: $0 <version-without-v> [headless|x11]}"
OZONE="${2:-headless}"
RELEASE_REPO="${RELEASE_REPO:-jmagly/carbonyl}"

case "$OZONE" in
  headless) ASSET="carbonyl-${VERSION}-x86_64-unknown-linux-gnu.tgz" ;;
  x11)      ASSET="carbonyl-${VERSION}-x11-x86_64-unknown-linux-gnu.tgz" ;;
  *) echo "ERROR: unknown ozone variant '$OZONE' (expected headless or x11)" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/build/carbonyl-runtime"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading ${RELEASE_REPO} release v${VERSION}: ${ASSET}"
gh release download "v${VERSION}" -R "$RELEASE_REPO" -p "$ASSET" -p "${ASSET}.sha256" -D "$TMP"

echo "==> Verifying SHA256"
( cd "$TMP" && sha256sum -c "${ASSET}.sha256" )

echo "==> Extracting to ${DEST}"
rm -rf "$DEST"
mkdir -p "$DEST"
tar -xzf "$TMP/$ASSET" -C "$DEST" --strip-components=1

echo "==> Smoke test"
"$DEST/carbonyl" --version
echo "==> Ready: docker build -f build/Dockerfile.runtime build/"
