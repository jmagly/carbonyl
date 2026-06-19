#!/usr/bin/env bash
# mutsu-build-macos.sh - Drive the macOS ARM runtime build on mutsu over SSH,
# DETACHED so a dropped SSH session cannot kill a multi-hour build.
#
# The remote host owns the large Chromium checkout at /Volumes/build/carbonyl.
# Pattern: SSH (short) to stage + launch the build under nohup+caffeinate on
# mutsu, logging to a file on /Volumes/build; then poll with short SSH calls
# until a done-marker (with exit code) appears. A transient SSH/runner blip
# fails a single poll iteration, not the build. Run #398 died at ~65% when the
# long-lived inline SSH session dropped — this removes that failure mode.

set -euo pipefail

host="${MUTSU_HOST:-mutsu}"
remote_dir="${MUTSU_CARBONYL_DIR:-/Volumes/build/carbonyl}"
branch="${MUTSU_BRANCH:-main}"
ssh_config="${MUTSU_SSH_CONFIG:-}"
jobs=""
ozone="headless"
publish="false"
poll_secs="${MUTSU_POLL_SECS:-60}"
max_wait_secs="${MUTSU_MAX_WAIT_SECS:-36000}"   # 10h ceiling

usage() {
  cat <<'USAGE'
mutsu-build-macos.sh - Drive the macOS ARM runtime build on mutsu over SSH (detached).

Launches the build detached on mutsu (nohup+caffeinate, logging to a run dir on
/Volumes/build) and polls for completion with short SSH calls, so a dropped SSH
session does not kill the build.

Usage:
  bash scripts/mutsu-build-macos.sh [--host mutsu] [--ssh-config FILE] [--remote-dir /Volumes/build/carbonyl] [--branch main] [--jobs N] [--ozone headless] [--publish]

Options:
  --host HOST         SSH target. Defaults to MUTSU_HOST or mutsu.
  --ssh-config FILE   SSH config file. Defaults to MUTSU_SSH_CONFIG when set.
  --remote-dir DIR    Remote Carbonyl checkout. Defaults to MUTSU_CARBONYL_DIR or /Volumes/build/carbonyl.
  --branch BRANCH     Remote branch to fast-forward. Defaults to MUTSU_BRANCH or main.
  --jobs N, -j N      Ninja parallelism passed to build-macos.sh.
  --ozone NAME        Ozone tag for build/publish. Defaults to headless.
  --publish           Run runtime-push.sh arm64 after smoke. Requires GITEA_TOKEN.
  -h, --help          Show this help.

Env: MUTSU_POLL_SECS (poll interval, default 60), MUTSU_MAX_WAIT_SECS (ceiling, default 36000).
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

run_dir="$(dirname "$remote_dir")/.carbonyl-macos-run"

printf -v remote_dir_q '%q' "$remote_dir"
printf -v run_dir_q     '%q' "$run_dir"
printf -v branch_q      '%q' "$branch"
printf -v jobs_q        '%q' "$jobs"
printf -v publish_q     '%q' "$publish"
printf -v ozone_q       '%q' "$ozone"

ssh_args=(-o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ConnectTimeout=15)
[ -n "$ssh_config" ] && ssh_args+=(-F "$ssh_config")
rssh() { ssh "${ssh_args[@]}" "$host" "$@"; }

echo "[drive] target=$host dir=$remote_dir run_dir=$run_dir branch=$branch publish=$publish jobs=${jobs:-auto} poll=${poll_secs}s"

# ---- the build itself; runs ON mutsu, detached. Reads RUN_DIR / ozone / args. ----
build_body() {
cat <<'REMOTE'
set -euo pipefail
remote_dir="$1"; branch="$2"; jobs="$3"; publish="$4"
[ -f "${RUN_DIR:-/nonexistent}/.token" ] && . "${RUN_DIR}/.token"
run_awake() { if command -v caffeinate >/dev/null 2>&1; then caffeinate -dimsu "$@"; else "$@"; fi; }
cd "$remote_dir"
echo "[mutsu] verifying clean worktree"
if [ -n "$(git status --porcelain)" ]; then git status --short; echo "ERROR: remote worktree not clean" >&2; exit 1; fi
scratch="$(cd "$remote_dir/.." && pwd)/.carbonyl-scratch"
export TMPDIR="$scratch/tmp"; export CARGO_HOME="${CARGO_HOME:-$scratch/cargo}"
mkdir -p "$TMPDIR" "$CARGO_HOME"
echo "[mutsu] build scratch on external volume: $scratch"
echo "[mutsu] updating $branch"
git fetch origin "$branch"; git checkout "$branch"; git merge --ff-only "origin/$branch"
echo "[mutsu] syncing Chromium"; run_awake bash scripts/gclient.sh sync
echo "[mutsu] applying patches"; bash scripts/patches.sh apply
build_args=(--ozone "${CARBONYL_OZONE_TAG:-headless}")
[ -n "$jobs" ] && build_args+=(--jobs "$jobs")
echo "[mutsu] building macOS runtime"; run_awake bash scripts/build-macos.sh "${build_args[@]}"
echo "[mutsu] smoke: carbonyl --version"; ( cd build/pre-built/aarch64-apple-darwin && ./carbonyl --version )
if [ "$publish" = "true" ]; then
  : "${GITEA_TOKEN:?GITEA_TOKEN must be set for publish}"
  echo "[mutsu] publishing runtime asset"; bash scripts/runtime-push.sh arm64
fi
echo "[mutsu] complete"
REMOTE
}

# ---- stage: run dir + build script (+ token if publishing) ----
echo "[drive] staging build on mutsu"
build_body | rssh "mkdir -p $run_dir_q && cat > $run_dir_q/build.sh && chmod 700 $run_dir_q/build.sh && rm -f $run_dir_q/build.done $run_dir_q/build.log"
if [ "$publish" = "true" ]; then
  printf 'export GITEA_TOKEN=%q\n' "$GITEA_TOKEN" | rssh "umask 077; cat > $run_dir_q/.token"
fi

# ---- launch detached (nohup+caffeinate); all std fds redirected so ssh returns ----
echo "[drive] launching detached build"
rssh "cd $run_dir_q && RUN_DIR=$run_dir_q CARBONYL_OZONE_TAG=$ozone_q nohup sh -c '
  caffeinate -dimsu bash build.sh $remote_dir_q $branch_q $jobs_q $publish_q > build.log 2>&1
  echo \$? > build.done
' </dev/null >/dev/null 2>&1 & echo launched"

# ---- poll: short SSH calls; stream new log lines; tolerate transient failures ----
echo "[drive] polling for completion (interval ${poll_secs}s, ceiling ${max_wait_secs}s)"
waited=0; seen=0; misses=0
while [ "$waited" -lt "$max_wait_secs" ]; do
  total="$(rssh "wc -l < $run_dir_q/build.log 2>/dev/null || echo $seen" 2>/dev/null || echo "$seen")"
  total="${total//[^0-9]/}"; [ -n "$total" ] || total="$seen"
  if [ "$total" -gt "$seen" ]; then
    rssh "sed -n '$((seen+1)),\${p}' $run_dir_q/build.log 2>/dev/null" 2>/dev/null || true
    seen="$total"
  fi
  if done_code="$(rssh "cat $run_dir_q/build.done 2>/dev/null" 2>/dev/null)" && [ -n "$done_code" ]; then
    done_code="${done_code//[^0-9]/}"; [ -n "$done_code" ] || done_code=1
    echo "[drive] remote build finished, exit=$done_code"
    [ "$publish" = "true" ] && rssh "rm -f $run_dir_q/.token" 2>/dev/null || true
    echo "[drive] ---- final log tail ----"
    rssh "tail -n 40 $run_dir_q/build.log 2>/dev/null" 2>/dev/null || true
    exit "$done_code"
  fi
  sleep "$poll_secs"; waited=$((waited + poll_secs))
done

echo "[drive] ERROR: build did not finish within ${max_wait_secs}s (still running detached on mutsu: $run_dir/build.log)" >&2
[ "$publish" = "true" ] && rssh "rm -f $run_dir_q/.token" 2>/dev/null || true
exit 1
