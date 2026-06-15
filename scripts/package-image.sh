#!/usr/bin/env bash
# package-image.sh — build (and optionally push) the Carbonyl runtime
# container image (#132, ADR-004).
#
# Builds ghcr.io/jmagly/carbonyl from a pre-built runtime payload by installing
# the same native .deb that release.yml publishes (#129). Host-agnostic: works
# on the titan CI runner and on a dev box for test/debug. Local builds are for
# test/debug only — real publishes go through .gitea/workflows/publish-image.yml.
#
# Usage:
#   bash scripts/package-image.sh --payload DIR --version 0.2.0-alpha.9 \
#        [--arch amd64] [--image ghcr.io/jmagly/carbonyl] \
#        [--out build/image-work] [--push] [--no-latest]
#
#   --payload DIR   Extracted runtime payload (the x86_64-unknown-linux-gnu
#                   directory: carbonyl, libcarbonyl.so, icudtl.dat, …). Required.
#   --version V     Semantic version, e.g. 0.2.0-alpha.9. Required.
#   --arch A        amd64 (default). arm64 is reserved for after #116.
#   --image NAME    Image repository (default ghcr.io/jmagly/carbonyl).
#   --out DIR       Scratch dir for the .deb + build context (default a mktemp).
#   --push          docker login + push :<version> and :latest. Requires
#                   GHCR_TOKEN in the environment; GHCR_USER defaults to jmagly.
#   --no-latest     Tag/push only :<version>, not :latest.
#
# Push auth (only read when --push):
#   GHCR_USER   ghcr username / namespace owner (default: jmagly)
#   GHCR_TOKEN  PAT with write:packages on the ghcr.io/<GHCR_USER> namespace
#
# Token is read from the environment and piped to `docker login --password-stdin`
# — never passed on the command line, never echoed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

image="ghcr.io/jmagly/carbonyl"
arch="amd64"
payload=""
version=""
out=""
push=0
want_latest=1

while [ $# -gt 0 ]; do
  case "$1" in
    --payload) payload="$2"; shift 2 ;;
    --payload=*) payload="${1#--payload=}"; shift ;;
    --version) version="$2"; shift 2 ;;
    --version=*) version="${1#--version=}"; shift ;;
    --arch) arch="$2"; shift 2 ;;
    --arch=*) arch="${1#--arch=}"; shift ;;
    --image) image="$2"; shift 2 ;;
    --image=*) image="${1#--image=}"; shift ;;
    --out) out="$2"; shift 2 ;;
    --out=*) out="${1#--out=}"; shift ;;
    --push) push=1; shift ;;
    --no-latest) want_latest=0; shift ;;
    -h|--help) sed -n '2,38p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$payload" ] || { echo "ERROR: --payload is required" >&2; exit 2; }
[ -n "$version" ] || { echo "ERROR: --version is required" >&2; exit 2; }
[ -d "$payload" ] || { echo "ERROR: payload dir not found: $payload" >&2; exit 2; }
[ -x "$payload/carbonyl" ] || { echo "ERROR: $payload/carbonyl missing or not executable" >&2; exit 2; }

case "$arch" in
  amd64) docker_platform="linux/amd64" ;;
  arm64) echo "ERROR: arm64 image is deferred until the arm64-linux runtime exists (#116)" >&2; exit 2 ;;
  *) echo "ERROR: --arch must be amd64 (arm64 pending #116)" >&2; exit 2 ;;
esac

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found on PATH" >&2; exit 1; }

# Scratch dir for the intermediate .deb and the docker build context.
cleanup_out=0
if [ -z "$out" ]; then
  out="$(mktemp -d "${TMPDIR:-/tmp}/carbonyl-image.XXXXXX")"
  cleanup_out=1
fi
mkdir -p "$out"
debdir="$out/deb"
ctx="$out/context"
rm -rf "$debdir" "$ctx"
mkdir -p "$debdir" "$ctx"

cleanup() {
  if [ "$cleanup_out" -eq 1 ]; then
    rm -rf "$out" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "[image] building .deb from payload via package-linux.sh"
bash "$REPO_ROOT/scripts/package-linux.sh" \
  --payload "$payload" --version "$version" --arch "$arch" \
  --formats deb --out "$debdir"

deb="$(find "$debdir" -maxdepth 1 -type f -name '*.deb' | head -1)"
[ -n "$deb" ] || { echo "ERROR: package-linux.sh produced no .deb in $debdir" >&2; exit 1; }
echo "[image] using $(basename "$deb") ($(du -h "$deb" | cut -f1))"

# Assemble the build context: exactly the Dockerfile + the .deb.
cp "$REPO_ROOT/build/Dockerfile.runtime" "$ctx/Dockerfile"
cp "$deb" "$ctx/carbonyl.deb"

tag_version="${image}:${version}"
build_args=(--platform "$docker_platform" --tag "$tag_version")
[ "$want_latest" -eq 1 ] && build_args+=(--tag "${image}:latest")

echo "[image] docker build ${tag_version}$([ "$want_latest" -eq 1 ] && echo " + :latest")"
docker build "${build_args[@]}" "$ctx"

echo "[image] smoke: carbonyl --version inside the image"
docker run --rm --entrypoint /usr/bin/carbonyl "$tag_version" --version

if [ "$push" -eq 1 ]; then
  : "${GHCR_USER:=jmagly}"
  [ -n "${GHCR_TOKEN:-}" ] || { echo "ERROR: --push requires GHCR_TOKEN in the environment" >&2; exit 1; }
  registry="${image%%/*}"   # e.g. ghcr.io
  echo "[image] docker login ${registry} as ${GHCR_USER}"
  printf '%s' "$GHCR_TOKEN" | docker login "$registry" -u "$GHCR_USER" --password-stdin
  echo "[image] pushing ${tag_version}"
  docker push "$tag_version"
  if [ "$want_latest" -eq 1 ]; then
    echo "[image] pushing ${image}:latest"
    docker push "${image}:latest"
  fi
  docker logout "$registry" >/dev/null 2>&1 || true
  echo "[image] pushed ${tag_version}$([ "$want_latest" -eq 1 ] && echo " + :latest")"
else
  echo "[image] built locally (no --push). Test with:"
  echo "          docker run --rm -ti ${tag_version} https://example.com"
fi
