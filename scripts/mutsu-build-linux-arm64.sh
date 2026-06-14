#!/usr/bin/env bash
# mutsu-build-linux-arm64.sh - Drive the Linux ARM64 runtime build on mutsu.
#
# This is the #116 companion to mutsu-build-macos.sh. It uses mutsu only as
# the Apple Silicon host: the actual build runs in an aarch64 Linux Colima VM
# and inside the pinned carbonyl-builder image. The checkout is intentionally
# separate from /Volumes/build/carbonyl so Linux gclient/build state cannot
# disturb the macOS-native runtime tree.

set -euo pipefail

host="${MUTSU_HOST:-mutsu-agent}"
remote_dir="${MUTSU_LINUX_CARBONYL_DIR:-/Volumes/build/carbonyl-linux-arm64}"
branch="${MUTSU_BRANCH:-main}"
ssh_config="${MUTSU_SSH_CONFIG:-}"
profile="${MUTSU_COLIMA_PROFILE:-carbonyl-linux-arm64}"
colima_home="${MUTSU_COLIMA_HOME:-/Volumes/build/.colima}"
vm_build_dir="${MUTSU_VM_BUILD_DIR:-/mnt/lima-colima-${profile}/carbonyl-linux-arm64}"
cpus="${MUTSU_COLIMA_CPUS:-8}"
memory="${MUTSU_COLIMA_MEMORY:-12}"
disk="${MUTSU_COLIMA_DISK:-500}"
jobs=""
ozone="headless"
publish="false"
skip_sync="false"
preflight="false"
gitea_user="${GITEA_USER:-roctinam}"

usage() {
  cat <<'USAGE'
mutsu-build-linux-arm64.sh - Build/publish aarch64-unknown-linux-gnu on mutsu.

The remote host runs an isolated Colima profile and checkout:
  profile:    carbonyl-linux-arm64
  checkout:   /Volumes/build/carbonyl-linux-arm64
  artifact:   build/pre-built/aarch64-unknown-linux-gnu.tgz

Usage:
  bash scripts/mutsu-build-linux-arm64.sh [options]

Options:
  --host HOST         SSH target. Defaults to MUTSU_HOST or mutsu-agent.
  --ssh-config FILE   SSH config file. Defaults to MUTSU_SSH_CONFIG when set.
  --remote-dir DIR    Remote Linux checkout. Defaults to /Volumes/build/carbonyl-linux-arm64.
  --branch BRANCH     Remote branch to fast-forward. Defaults to main.
  --profile NAME      Colima profile. Defaults to carbonyl-linux-arm64.
  --colima-home DIR   Colima home directory. Defaults to /Volumes/build/.colima.
  --vm-build-dir DIR  Linux VM-native build dir. Defaults to /mnt/lima-colima-<profile>/carbonyl-linux-arm64.
  --cpus N            Colima CPUs. Defaults to 8.
  --memory GiB        Colima memory in GiB. Defaults to 12.
  --disk GiB          Colima disk in GiB. Defaults to 500.
  --jobs N, -j N      Ninja parallelism passed to build.sh.
  --ozone NAME        Ozone tag for build/publish. Defaults to headless.
  --preflight         Check mutsu tooling/profile/checkout state, then exit.
  --skip-sync         Skip Chromium gclient sync; still resets/applies patches.
  --publish           Run runtime-push.sh arm64 after smoke. Requires local GITEA_TOKEN.
  GITEA_USER          Registry username for docker login when GITEA_TOKEN is set. Defaults to roctinam.
  -h, --help          Show this help.

Examples:
  bash scripts/mutsu-build-linux-arm64.sh --ssh-config /home/roctinam/.ssh/config --jobs 2
  GITEA_TOKEN="$(cat ~/.config/gitea/token)" bash scripts/mutsu-build-linux-arm64.sh --publish
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
    --profile) profile="$2"; shift 2 ;;
    --profile=*) profile="${1#--profile=}"; shift ;;
    --colima-home) colima_home="$2"; shift 2 ;;
    --colima-home=*) colima_home="${1#--colima-home=}"; shift ;;
    --vm-build-dir) vm_build_dir="$2"; shift 2 ;;
    --vm-build-dir=*) vm_build_dir="${1#--vm-build-dir=}"; shift ;;
    --cpus) cpus="$2"; shift 2 ;;
    --cpus=*) cpus="${1#--cpus=}"; shift ;;
    --memory) memory="$2"; shift 2 ;;
    --memory=*) memory="${1#--memory=}"; shift ;;
    --disk) disk="$2"; shift 2 ;;
    --disk=*) disk="${1#--disk=}"; shift ;;
    --jobs|-j) jobs="$2"; shift 2 ;;
    --jobs=*) jobs="${1#--jobs=}"; shift ;;
    -j*) jobs="${1#-j}"; shift ;;
    --ozone) ozone="$2"; shift 2 ;;
    --ozone=*) ozone="${1#--ozone=}"; shift ;;
    --preflight) preflight="true"; shift ;;
    --skip-sync) skip_sync="true"; shift ;;
    --publish) publish="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for value_name in cpus memory disk; do
  value="${!value_name}"
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: --${value_name} must be a positive integer" >&2
    exit 2
  fi
done
if [ -n "$jobs" ] && ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: --jobs must be a positive integer" >&2
  exit 2
fi
case "$skip_sync" in true|false) ;; *) echo "ERROR: skip_sync must be true/false" >&2; exit 2 ;; esac
case "$preflight" in true|false) ;; *) echo "ERROR: preflight must be true/false" >&2; exit 2 ;; esac
case "$publish" in true|false) ;; *) echo "ERROR: publish must be true/false" >&2; exit 2 ;; esac

if [ "$publish" = "true" ]; then
  : "${GITEA_TOKEN:?GITEA_TOKEN must be set locally when --publish is used}"
fi

printf -v remote_dir_q '%q' "$remote_dir"
printf -v branch_q '%q' "$branch"
printf -v jobs_q '%q' "$jobs"
printf -v publish_q '%q' "$publish"
printf -v ozone_q '%q' "$ozone"
printf -v user_q '%q' "$gitea_user"
printf -v profile_q '%q' "$profile"
printf -v colima_home_q '%q' "$colima_home"
printf -v vm_build_dir_q '%q' "$vm_build_dir"
printf -v cpus_q '%q' "$cpus"
printf -v memory_q '%q' "$memory"
printf -v disk_q '%q' "$disk"
printf -v skip_sync_q '%q' "$skip_sync"
printf -v preflight_q '%q' "$preflight"

echo "[mutsu-linux] target=$host dir=$remote_dir branch=$branch profile=$profile colima_home=$colima_home vm_build_dir=$vm_build_dir publish=$publish jobs=${jobs:-auto}"

ssh_args=(-o BatchMode=yes)
if [ -n "$ssh_config" ]; then
  ssh_args+=(-F "$ssh_config")
fi

remote_token_file=""
if [ "$publish" = "true" ]; then
  remote_token_file="$(
    printf '%s' "$GITEA_TOKEN" | ssh "${ssh_args[@]}" "$host" \
      'umask 077; token_file="$(mktemp /tmp/carbonyl-gitea-token.XXXXXX)"; cat > "$token_file"; printf "%s" "$token_file"'
  )"
fi
printf -v remote_token_file_q '%q' "$remote_token_file"

# shellcheck disable=SC2029 # values are intentionally quoted locally with printf %q.
ssh "${ssh_args[@]}" "$host" \
  "GITEA_USER=$user_q CARBONYL_OZONE_TAG=$ozone_q PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin bash -s -- $remote_dir_q $branch_q $jobs_q $publish_q $profile_q $colima_home_q $vm_build_dir_q $cpus_q $memory_q $disk_q $skip_sync_q $preflight_q $remote_token_file_q" <<'REMOTE'
set -euo pipefail

remote_dir="$1"; shift
branch="$1"; shift
jobs="$1"; shift
publish="$1"; shift
profile="$1"; shift
colima_home="$1"; shift
vm_build_dir="$1"; shift
cpus="$1"; shift
memory="$1"; shift
disk="$1"; shift
skip_sync="$1"; shift
preflight="$1"; shift
gitea_token_file="$1"; shift

cleanup_token_file() {
  if [ -n "${gitea_token_file:-}" ]; then
    rm -f "$gitea_token_file"
  fi
}
trap cleanup_token_file EXIT

if [ -n "$gitea_token_file" ]; then
  export GITEA_TOKEN="$(cat "$gitea_token_file")"
  rm -f "$gitea_token_file"
  gitea_token_file=""
fi

run_awake() {
  if command -v caffeinate >/dev/null 2>&1; then
    caffeinate -dimsu "$@"
  else
    "$@"
  fi
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found on mutsu: $1" >&2
    exit 1
  }
}

need git
need colima
need docker

repo_url="${MUTSU_REPO_URL:-git@git.integrolabs.net:roctinam/carbonyl.git}"
builder_image="${MUTSU_BUILDER_IMAGE:-}"
builder_source="override"
mkdir -p "$colima_home"
export COLIMA_HOME="$colima_home"

if [ "$preflight" = "true" ]; then
  echo "[mutsu-linux] preflight"
  uname -a
  df -h /Volumes/build 2>/dev/null || true
  echo "COLIMA_HOME=${COLIMA_HOME}"
  echo "vm_build_dir=${vm_build_dir}"
  colima list 2>/dev/null || true
  if colima status --profile "$profile" >/dev/null 2>&1; then
    colima ssh --profile "$profile" -- bash -lc "df -h / /mnt/lima-colima-${profile} 2>/dev/null || true; test -d '$vm_build_dir' && du -sh '$vm_build_dir' 2>/dev/null || true"
  fi
  docker context ls 2>/dev/null || true
  if [ -d "$remote_dir/.git" ]; then
    git -C "$remote_dir" status --short --branch
  else
    echo "[mutsu-linux] checkout missing; first build will clone ${repo_url}"
  fi
  echo "[mutsu-linux] preflight complete"
  exit 0
fi

mkdir -p "$(dirname "$remote_dir")"
if [ ! -d "$remote_dir/.git" ]; then
  echo "[mutsu-linux] cloning ${repo_url} -> ${remote_dir}"
  git clone "$repo_url" "$remote_dir"
fi

cd "$remote_dir"

echo "[mutsu-linux] verifying clean Linux checkout"
if [ -n "$(git status --porcelain)" ]; then
  git status --short
  echo "ERROR: remote Linux checkout is not clean; refusing to overwrite local changes" >&2
  exit 1
fi

echo "[mutsu-linux] updating ${branch}"
git fetch origin "$branch"
git checkout "$branch"
if ! git merge --ff-only "origin/$branch"; then
  echo "[mutsu-linux] ${branch} cannot fast-forward; aligning clean checkout to origin/${branch}"
  git reset --hard "origin/$branch"
fi

if [ -z "$builder_image" ]; then
  # The registry pin is currently linux/amd64. For #116, build the same
  # Dockerfile inside the aarch64 Colima VM so Chromium/Rust run natively.
  builder_image="carbonyl-builder:$(git rev-parse --short HEAD)-arm64"
  builder_source="local"
fi
echo "[mutsu-linux] builder image: ${builder_image} (${builder_source})"

if ! colima status --profile "$profile" >/dev/null 2>&1; then
  echo "[mutsu-linux] starting Colima profile ${profile}"
  colima start --profile "$profile" \
    --arch aarch64 \
    --runtime docker \
    --cpus "$cpus" \
    --memory "$memory" \
    --disk "$disk" \
    --mount "/Volumes/build:w"
else
  echo "[mutsu-linux] Colima profile ${profile} already running"
fi

export DOCKER_HOST="unix://${COLIMA_HOME}/${profile}/docker.sock"
docker version >/dev/null

echo "[mutsu-linux] preparing VM-native build dir ${vm_build_dir}"
colima ssh --profile "$profile" -- sudo mkdir -p "$vm_build_dir"

if [ "$builder_source" = "local" ]; then
  echo "[mutsu-linux] building local arm64 builder image"
  docker build \
    --platform linux/arm64 \
    -f build/Dockerfile.builder \
    -t "$builder_image" \
    .
else
  if [ -n "${GITEA_TOKEN:-}" ]; then
    echo "[mutsu-linux] logging in to git.integrolabs.net registry as ${GITEA_USER:-roctinam}"
    printf '%s' "${GITEA_TOKEN}" | docker login git.integrolabs.net \
      -u "${GITEA_USER:-roctinam}" \
      --password-stdin
  fi
  docker pull "$builder_image"
fi

container_root="/workspace"
docker_run=(
  docker run --rm
  -v "${remote_dir}:${container_root}"
  -v "${vm_build_dir}:/build"
  -w "${container_root}"
  -e CARBONYL_ROOT="${container_root}"
  -e CHROMIUM_ROOT="/build/chromium"
  -e CHROMIUM_SRC="/build/chromium/src"
  -e DEPOT_TOOLS_ROOT="${container_root}/chromium/depot_tools"
  -e DEPOT_TOOLS_UPDATE=0
)

if [ "$skip_sync" != "true" ]; then
  echo "[mutsu-linux] syncing Chromium"
  run_awake "${docker_run[@]}" "$builder_image" bash -lc '
    set -euo pipefail
    git config --global --add safe.directory "*"
    mkdir -p "${CHROMIUM_ROOT}"
    cp chromium/.gclient "${CHROMIUM_ROOT}/.gclient"

    TARGET_VERSION="$(sed -n "s/.*src\.git@\([^\"]*\)\".*/\1/p" chromium/.gclient | head -1)"
    TARGET_SHA="$(sed -n "s/^chromium_upstream=\"\([^\"]*\)\".*/\1/p" scripts/patches.sh | head -1)"
    if [ -z "${TARGET_VERSION}" ] || [ -z "${TARGET_SHA}" ]; then
      echo "[sync-chromium] ERROR: could not resolve .gclient version or chromium_upstream" >&2
      exit 1
    fi

    if [ -d "${CHROMIUM_SRC}/.git" ] && ! git -C "${CHROMIUM_SRC}" rev-parse --verify HEAD >/dev/null 2>&1; then
      echo "[sync-chromium] removing incomplete git checkout ${CHROMIUM_SRC}"
      rm -rf "${CHROMIUM_SRC}"
    fi

    if [ ! -d "${CHROMIUM_SRC}/.git" ]; then
      if [ -e "${CHROMIUM_SRC}" ]; then
        echo "[sync-chromium] removing incomplete non-git ${CHROMIUM_SRC}"
        rm -rf "${CHROMIUM_SRC}"
      fi
      mkdir -p "$(dirname "${CHROMIUM_SRC}")"
      echo "[sync-chromium] cloning Chromium src checkout"
      git clone --no-checkout https://chromium.googlesource.com/chromium/src.git "${CHROMIUM_SRC}"
    fi

    CURRENT_HEAD="$(git -C "${CHROMIUM_SRC}" rev-parse HEAD 2>/dev/null || true)"
    echo "[sync-chromium] current HEAD before: ${CURRENT_HEAD:-<none>}"
    echo "[sync-chromium] target version: ${TARGET_VERSION}"
    echo "[sync-chromium] target SHA: ${TARGET_SHA}"

    if [ "${CURRENT_HEAD}" = "${TARGET_SHA}" ] && git -C "${CHROMIUM_SRC}" cat-file -e "${TARGET_SHA}^{commit}"; then
      echo "[sync-chromium] already at .gclient pin; no fetch or sync needed"
    else
      echo "[sync-chromium] fetching Chromium tag ${TARGET_VERSION}"
      git -C "${CHROMIUM_SRC}" fetch --progress origin "refs/tags/${TARGET_VERSION}:refs/tags/${TARGET_VERSION}"
      echo "[sync-chromium] checking out Chromium tag ${TARGET_VERSION}"
      git -C "${CHROMIUM_SRC}" checkout "${TARGET_VERSION}"
    fi

    source scripts/env.sh
    bash scripts/gclient.sh sync --no-history
    git -C "${CHROMIUM_SRC}" cat-file -e "${TARGET_SHA}^{commit}"
    FINAL_HEAD="$(git -C "${CHROMIUM_SRC}" rev-parse HEAD)"
    echo "[sync-chromium] final HEAD after: ${FINAL_HEAD}"
  '
else
  echo "[mutsu-linux] skipping gclient sync by request"
fi

echo "[mutsu-linux] resetting Chromium source and applying patches"
run_awake "${docker_run[@]}" "$builder_image" bash -lc '
  set -euo pipefail
  git config --global --add safe.directory "*"
  if [ -d "${CHROMIUM_SRC}/.git" ]; then
    git -C "${CHROMIUM_SRC}" am --abort 2>/dev/null || true
    git -C "${CHROMIUM_SRC}" rebase --abort 2>/dev/null || true
    git -C "${CHROMIUM_SRC}" reset --hard HEAD
    git -C "${CHROMIUM_SRC}" clean -fd || true
  fi
  source scripts/env.sh
  bash scripts/patches.sh apply
'

echo "[mutsu-linux] running gn gen"
run_awake "${docker_run[@]}" "$builder_image" bash -lc '
  set -euo pipefail
  source scripts/env.sh
  mkdir -p "${CHROMIUM_SRC}/out/Default"
  cp src/browser/args.gn "${CHROMIUM_SRC}/out/Default/args.gn"
  case "${CARBONYL_OZONE_TAG:-headless}" in
    headless)
      echo "[mutsu-linux] keeping headless Ozone args"
      ;;
    x11)
      sed -i "s/^ozone_platform = \"headless\"/ozone_platform = \"x11\"/" "${CHROMIUM_SRC}/out/Default/args.gn"
      sed -i "s/^ozone_platform_x11 = false/ozone_platform_x11 = true/" "${CHROMIUM_SRC}/out/Default/args.gn"
      sed -i "s/^use_xkbcommon = false/use_xkbcommon = true/" "${CHROMIUM_SRC}/out/Default/args.gn"
      echo "[mutsu-linux] switched generated args to x11 Ozone"
      ;;
    *)
      echo "ERROR: unsupported --ozone '${CARBONYL_OZONE_TAG:-}' for Linux arm64 build" >&2
      exit 2
      ;;
  esac
  cd "${CHROMIUM_SRC}"
  gn gen out/Default
'

build_args=(Default arm64)
if [ -n "$jobs" ]; then
  build_args+=("-j" "$jobs")
fi

echo "[mutsu-linux] building aarch64-unknown-linux-gnu runtime"
run_awake "${docker_run[@]}" "$builder_image" bash -lc '
  set -euo pipefail
  source scripts/env.sh
  bash scripts/build.sh "$@"
' bash "${build_args[@]}"

echo "[mutsu-linux] packaging runtime"
run_awake "${docker_run[@]}" "$builder_image" bash -lc '
  set -euo pipefail
  source scripts/env.sh
  bash scripts/copy-binaries.sh Default arm64
'

echo "[mutsu-linux] smoke: carbonyl --version"
run_awake "${docker_run[@]}" "$builder_image" bash -lc '
  set -euo pipefail
  cd build/pre-built/aarch64-unknown-linux-gnu
  LD_LIBRARY_PATH="$PWD${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ./carbonyl --version
'

if [ "$publish" = "true" ]; then
  : "${GITEA_TOKEN:?GITEA_TOKEN must be set for publish}"
  echo "[mutsu-linux] publishing runtime asset"
  run_awake "${docker_run[@]}" \
    -e GITEA_TOKEN="${GITEA_TOKEN}" \
    -e CARBONYL_OZONE_TAG="${CARBONYL_OZONE_TAG:-headless}" \
    "$builder_image" bash -lc '
      set -euo pipefail
      source scripts/env.sh
      bash scripts/runtime-push.sh arm64
    '
fi

echo "[mutsu-linux] complete"
REMOTE
