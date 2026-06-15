#!/usr/bin/env bash
# mutsu-package-macos.sh — release-time driver: build the UNSIGNED macOS
# installer (.pkg + .dmg) on mutsu for a tagged version and upload it to the
# versioned release on Gitea (+ GitHub mirror). (#129, ADR-003)
#
# Why a separate driver: macOS installers are version-stamped, so they are built
# at release time (version known), and only mutsu can run pkgbuild/hdiutil. The
# Linux installers are produced automatically in release.yml on titan; this is
# the macOS counterpart, driven over SSH like scripts/mutsu-build-macos.sh.
#
# All build scratch + output live on mutsu's external volume (/Volumes/build);
# the boot disk is small and can run full.
#
# Prereq: the macOS runtime payload for the tag's hash must exist on mutsu
# (build/pre-built/aarch64-apple-darwin). Produce it with
# scripts/mutsu-build-macos.sh first. If absent, this driver tries
# runtime-pull.sh arm64 macos.
#
# Usage:
#   GITEA_TOKEN=<tok> [GH_MIRROR_TOKEN=<tok>] \
#     bash scripts/mutsu-package-macos.sh --version 0.2.0-alpha.9 \
#       [--host mutsu-agent] [--remote-dir /Volumes/build/carbonyl] [--gitea-only]
#
# Tokens are read from the environment (or GITEA_TOKEN from ~/.config/gitea/token
# if unset). GH_MIRROR_TOKEN enables the GitHub mirror upload; without it the
# GitHub step is skipped with a warning.

set -euo pipefail

host="${MUTSU_HOST:-mutsu-agent}"
remote_dir="${MUTSU_CARBONYL_DIR:-/Volumes/build/carbonyl}"
branch="${MUTSU_BRANCH:-main}"
version=""
arch="arm64"
gitea_only="false"
scratch_base="/Volumes/build/.carbonyl-scratch"

GITEA_REPO="roctinam/carbonyl"
GITEA_API="https://git.integrolabs.net/api/v1/repos/${GITEA_REPO}"
GH_API="https://api.github.com/repos/jmagly/carbonyl"
GH_UPLOAD="https://uploads.github.com/repos/jmagly/carbonyl"

usage() { sed -n '2,30p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --version=*) version="${1#--version=}"; shift ;;
    --host) host="$2"; shift 2 ;;
    --host=*) host="${1#--host=}"; shift ;;
    --remote-dir) remote_dir="$2"; shift 2 ;;
    --remote-dir=*) remote_dir="${1#--remote-dir=}"; shift ;;
    --branch) branch="$2"; shift 2 ;;
    --branch=*) branch="${1#--branch=}"; shift ;;
    --gitea-only) gitea_only="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$version" ] || { echo "ERROR: --version is required (e.g. 0.2.0-alpha.9)" >&2; exit 2; }
tag="v${version#v}"; version="${tag#v}"

# Tokens (never logged).
if [ -z "${GITEA_TOKEN:-}" ] && [ -f "$HOME/.config/gitea/token" ]; then
  GITEA_TOKEN="$(cat "$HOME/.config/gitea/token")"
fi
[ -n "${GITEA_TOKEN:-}" ] || { echo "ERROR: GITEA_TOKEN not set (and ~/.config/gitea/token absent)" >&2; exit 1; }

ssh_args=(-o BatchMode=yes)
remote() { ssh "${ssh_args[@]}" "$host" "$@"; }

printf -v rd_q '%q' "$remote_dir"
printf -v br_q '%q' "$branch"
printf -v ver_q '%q' "$version"
printf -v arch_q '%q' "$arch"
printf -v sb_q '%q' "$scratch_base"
printf -v tok_q '%q' "$GITEA_TOKEN"

echo "[mutsu-pkg] host=$host dir=$remote_dir version=$version arch=$arch"

# ── 1. build the installer on mutsu (external scratch) ──────────────────────
remote "GITEA_TOKEN=$tok_q bash -s -- $rd_q $br_q $ver_q $arch_q $sb_q" <<'REMOTE'
set -euo pipefail
remote_dir="$1"; branch="$2"; version="$3"; arch="$4"; scratch_base="$5"

cd "$remote_dir"
echo "[mutsu] verifying clean worktree"
if [ -n "$(git status --porcelain)" ]; then
  git status --short
  echo "ERROR: remote worktree not clean; refusing to proceed" >&2
  exit 1
fi
echo "[mutsu] updating $branch"
git fetch origin "$branch"
git checkout "$branch"
git merge --ff-only "origin/$branch"

payload="build/pre-built/aarch64-apple-darwin"
if [ ! -f "$payload/carbonyl" ]; then
  echo "[mutsu] payload missing; pulling runtime-<hash> macOS asset"
  bash scripts/runtime-pull.sh arm64 macos
fi
[ -f "$payload/carbonyl" ] || { echo "ERROR: macOS payload still missing: $payload" >&2; exit 1; }

mkdir -p "$scratch_base/tmp" "$scratch_base/pkgout"
export TMPDIR="$scratch_base/tmp"
rm -f "$scratch_base/pkgout/"carbonyl-*-macos-*.pkg "$scratch_base/pkgout/"carbonyl-*-macos-*.dmg

run_awake() { if command -v caffeinate >/dev/null 2>&1; then caffeinate -dimsu "$@"; else "$@"; fi; }
run_awake bash scripts/package-macos.sh --payload "$payload" --version "$version" --arch "$arch" --out "$scratch_base/pkgout"

echo "[mutsu] built:"
ls -lh "$scratch_base/pkgout/"carbonyl-"$version"-macos-"$arch".*
REMOTE

# ── 2. stream the artifacts back ────────────────────────────────────────────
localout="$(mktemp -d)"; trap 'rm -rf "$localout"' EXIT
pkg="carbonyl-${version}-macos-${arch}.pkg"
dmg="carbonyl-${version}-macos-${arch}.dmg"
printf -v po_q '%q' "${scratch_base}/pkgout"
echo "[mutsu-pkg] fetching artifacts back"
remote "cd $po_q && tar cf - $(printf '%q ' "$pkg" "$dmg")" | tar xf - -C "$localout"
[ -f "$localout/$pkg" ] && [ -f "$localout/$dmg" ] || { echo "ERROR: artifacts not received" >&2; exit 1; }
( cd "$localout" && sha256sum "$pkg" > "$pkg.sha256" && sha256sum "$dmg" > "$dmg.sha256" )
echo "[mutsu-pkg] local artifacts:"; ls -lh "$localout"/carbonyl-* | sed 's/^/  /'

# ── 3. upload to the versioned Gitea release ────────────────────────────────
echo "[mutsu-pkg] resolving Gitea release for ${tag}"
rid="$(curl -sf -H "Authorization: token ${GITEA_TOKEN}" "${GITEA_API}/releases/tags/${tag}" 2>/dev/null | jq -r '.id // empty')"
[ -n "$rid" ] || { echo "ERROR: Gitea release ${tag} not found; run release.yml first" >&2; exit 1; }
assets_api="${GITEA_API}/releases/${rid}/assets"
for f in "$pkg" "$pkg.sha256" "$dmg" "$dmg.sha256"; do
  old="$(curl -sf -H "Authorization: token ${GITEA_TOKEN}" "${assets_api}" | jq -r ".[] | select(.name==\"${f}\") | .id" 2>/dev/null || true)"
  [ -n "$old" ] && curl -sf -X DELETE -H "Authorization: token ${GITEA_TOKEN}" "${assets_api}/${old}" >/dev/null
  curl -sf -X POST "${assets_api}" -H "Authorization: token ${GITEA_TOKEN}" \
    -F "attachment=@${localout}/${f};filename=${f}" >/dev/null
  echo "[mutsu-pkg] gitea: uploaded ${f}"
done

# ── 4. mirror to GitHub (optional) ──────────────────────────────────────────
if [ "$gitea_only" = "true" ]; then
  echo "[mutsu-pkg] --gitea-only: skipping GitHub mirror"
elif [ -z "${GH_MIRROR_TOKEN:-}" ]; then
  echo "[mutsu-pkg] WARNING: GH_MIRROR_TOKEN unset; macOS installer NOT mirrored to GitHub"
else
  ghid="$(curl -sf -H "Authorization: Bearer ${GH_MIRROR_TOKEN}" "${GH_API}/releases/tags/${tag}" 2>/dev/null | jq -r '.id // empty')"
  if [ -z "$ghid" ]; then
    echo "[mutsu-pkg] WARNING: GitHub release ${tag} not found; skipping mirror"
  else
    for f in "$pkg" "$pkg.sha256" "$dmg" "$dmg.sha256"; do
      mime="$(file -b --mime-type "${localout}/${f}")"
      old="$(curl -sf -H "Authorization: Bearer ${GH_MIRROR_TOKEN}" "${GH_API}/releases/${ghid}/assets" | jq -r ".[] | select(.name==\"${f}\") | .id" 2>/dev/null || true)"
      [ -n "$old" ] && curl -sf -X DELETE -H "Authorization: Bearer ${GH_MIRROR_TOKEN}" "${GH_API}/releases/assets/${old}" >/dev/null
      curl -sf -X POST "${GH_UPLOAD}/releases/${ghid}/assets?name=${f}" \
        -H "Authorization: Bearer ${GH_MIRROR_TOKEN}" -H "Content-Type: ${mime}" \
        --data-binary "@${localout}/${f}" >/dev/null
      echo "[mutsu-pkg] github: mirrored ${f}"
    done
  fi
fi

echo "[mutsu-pkg] done: ${pkg} + ${dmg} attached to ${tag}"
