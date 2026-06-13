#!/usr/bin/env bash
# mutsu-build-macos.sh - Drive the macOS ARM runtime build on mutsu over SSH.
#
# The remote host owns the large Chromium checkout at /Volumes/build/carbonyl.
# This wrapper keeps the operator-side command repeatable: verify a clean remote
# tree, fast-forward main, sync Chromium, apply patches, build, smoke, and
# optionally publish the aarch64-apple-darwin runtime asset.

set -euo pipefail

host="${MUTSU_HOST:-mutsu}"
remote_dir="${MUTSU_CARBONYL_DIR:-/Volumes/build/carbonyl}"
branch="${MUTSU_BRANCH:-main}"
ssh_config="${MUTSU_SSH_CONFIG:-}"
jobs=""
ozone="headless"
publish="false"

usage() {
  cat <<'USAGE'
mutsu-build-macos.sh - Drive the macOS ARM runtime build on mutsu over SSH.

The remote host owns the large Chromium checkout at /Volumes/build/carbonyl.
This wrapper verifies a clean remote tree, fast-forwards main, syncs Chromium,
applies patches, builds, smokes, and optionally publishes the runtime asset.

Usage:
  bash scripts/mutsu-build-macos.sh [--host mutsu] [--ssh-config FILE] [--remote-dir /Volumes/build/carbonyl] [--branch main] [--jobs N] [--publish]

Options:
  --host HOST         SSH target. Defaults to MUTSU_HOST or mutsu.
  --ssh-config FILE   SSH config file. Defaults to MUTSU_SSH_CONFIG when set.
  --remote-dir DIR   Remote Carbonyl checkout. Defaults to MUTSU_CARBONYL_DIR or /Volumes/build/carbonyl.
  --branch BRANCH    Remote branch to fast-forward. Defaults to MUTSU_BRANCH or main.
  --jobs N, -j N     Ninja parallelism passed to build-macos.sh.
  --ozone NAME       Ozone tag for build/publish. Defaults to headless.
  --publish          Run runtime-push.sh arm64 after smoke. Requires local GITEA_TOKEN.
  -h, --help         Show this help.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) host="$2"; shift 2 ;;
    --host=*) host="${1#--host=}"; shift ;;
    --ssh-config) ssh_config="$2"; shift 2 ;;
    --ssh-config=*) ssh_config="${1#--ssh-config=}"; shift ;;
    --remote-dir) remote_dir="$2"; shift 2 ;;
    --remote-dir=*) remote_dir="${1#--remote-dir=}"; shift ;;
    --branch) branch="$2"; shift 2 ;;
    --branch=*) branch="${1#--branch=}"; shift ;;
    --jobs|-j) jobs="$2"; shift 2 ;;
    --jobs=*) jobs="${1#--jobs=}"; shift ;;
    -j*) jobs="${1#-j}"; shift ;;
    --ozone) ozone="$2"; shift 2 ;;
    --ozone=*) ozone="${1#--ozone=}"; shift ;;
    --publish) publish="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -n "$jobs" ] && ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: --jobs must be a positive integer" >&2
  exit 2
fi

if [ "$publish" = "true" ]; then
  : "${GITEA_TOKEN:?GITEA_TOKEN must be set locally when --publish is used}"
fi

printf -v remote_dir_q '%q' "$remote_dir"
printf -v branch_q '%q' "$branch"
printf -v jobs_q '%q' "$jobs"
printf -v publish_q '%q' "$publish"
printf -v ozone_q '%q' "$ozone"
printf -v token_q '%q' "${GITEA_TOKEN:-}"

echo "[mutsu] target=$host dir=$remote_dir branch=$branch publish=$publish jobs=${jobs:-auto}"

ssh_args=(-o BatchMode=yes)
if [ -n "$ssh_config" ]; then
  ssh_args+=(-F "$ssh_config")
fi

ssh "${ssh_args[@]}" "$host" \
  "GITEA_TOKEN=$token_q CARBONYL_OZONE_TAG=$ozone_q bash -s -- $remote_dir_q $branch_q $jobs_q $publish_q" <<'REMOTE'
set -euo pipefail

remote_dir="$1"
branch="$2"
jobs="$3"
publish="$4"

run_awake() {
  if command -v caffeinate >/dev/null 2>&1; then
    caffeinate -dimsu "$@"
  else
    "$@"
  fi
}

cd "$remote_dir"

echo "[mutsu] verifying clean worktree"
if [ -n "$(git status --porcelain)" ]; then
  git status --short
  echo "ERROR: remote worktree is not clean; refusing to overwrite local changes" >&2
  exit 1
fi

echo "[mutsu] updating $branch"
git fetch origin "$branch"
git checkout "$branch"
git merge --ff-only "origin/$branch"

echo "[mutsu] syncing Chromium"
run_awake bash scripts/gclient.sh sync

echo "[mutsu] applying patches"
bash scripts/patches.sh apply

build_args=(--ozone "${CARBONYL_OZONE_TAG:-headless}")
if [ -n "$jobs" ]; then
  build_args+=("--jobs" "$jobs")
fi

echo "[mutsu] building macOS runtime"
run_awake bash scripts/build-macos.sh "${build_args[@]}"

echo "[mutsu] smoke: carbonyl --version"
( cd build/pre-built/aarch64-apple-darwin && ./carbonyl --version )

if [ "$publish" = "true" ]; then
  : "${GITEA_TOKEN:?GITEA_TOKEN must be set for publish}"
  echo "[mutsu] publishing runtime asset"
  bash scripts/runtime-push.sh arm64
fi

echo "[mutsu] complete"
REMOTE
