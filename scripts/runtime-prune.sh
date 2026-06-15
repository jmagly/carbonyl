#!/usr/bin/env bash
# runtime-prune.sh — Keep only the latest runtime cut on Gitea releases.
#
# `build-runtime.yml` publishes a `runtime-<hash>` (and `runtime-x11-<hash>`)
# release on every push that changes the build inputs, so over time the
# Releases list fills with stale per-commit runtime cuts. This script enforces
# the "only keep the latest" policy: it deletes every `runtime-*` release AND
# its tag except the pair matching the keep-hash, leaving the full `v*` release
# cuts untouched.
#
# Keep-hash resolution:
#   $1 (positional)  — explicit hash to keep
#   else             — scripts/runtime-hash.sh (the current checkout's hash)
#
# Keeps both ozone variants for that hash:
#   runtime-<hash>          (headless)
#   runtime-x11-<hash>      (x11)
#
# Requirements:
#   - GITEA_TOKEN: token with write:release on roctinam/carbonyl
#   - jq, curl
#
# Usage:
#   GITEA_TOKEN=<token> bash scripts/runtime-prune.sh                  # keep current hash
#   GITEA_TOKEN=<token> bash scripts/runtime-prune.sh <hash>           # keep an explicit hash
#   GITEA_TOKEN=<token> bash scripts/runtime-prune.sh --dry-run        # show what would be deleted
#
# Safety:
#   - Refuses to run with an empty keep-hash (would delete everything).
#   - Never deletes the keep pair or any non-`runtime-*` release/tag.
#   - Tolerates already-deleted releases/tags (404) so it is idempotent and
#     safe to run from parallel matrix jobs.

set -euo pipefail

dry_run=false
keep_hash=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=true ;;
        -h|--help) sed -n '2,33p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
        *) keep_hash="$1" ;;
    esac
    shift
done

CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")"
export CARBONYL_ROOT
cd "$CARBONYL_ROOT"

: "${GITEA_TOKEN:?GITEA_TOKEN must be set (token with write:release scope)}"

GITEA_BASE="${GITEA_BASE:-https://git.integrolabs.net}"
GITEA_REPO="roctinam/carbonyl"
GITEA_API="$GITEA_BASE/api/v1"

if [ -z "$keep_hash" ]; then
    keep_hash="$(scripts/runtime-hash.sh)"
fi
# Hard guard: an empty keep-hash would make the keep-set match nothing and
# delete every runtime release. Refuse.
if [ -z "$keep_hash" ]; then
    echo "ERROR: could not resolve a keep-hash; refusing to prune" >&2
    exit 1
fi

keep_headless="runtime-$keep_hash"
keep_x11="runtime-x11-$keep_hash"

echo "[runtime-prune] keep-hash: $keep_hash"
echo "[runtime-prune] keeping:   $keep_headless, $keep_x11"
$dry_run && echo "[runtime-prune] DRY RUN — no deletions"

auth=(-H "Authorization: token $GITEA_TOKEN")

# Fetch releases (auto-prune keeps the list small; one page of 50 is ample).
releases="$(curl -sf "${auth[@]}" "$GITEA_API/repos/$GITEA_REPO/releases?limit=50" || true)"
if [ -z "$releases" ]; then
    echo "ERROR: could not list releases" >&2
    exit 1
fi

# runtime-* releases that are NOT the keep pair → "<id> <tag>" lines.
mapfile -t stale < <(echo "$releases" | jq -r --arg kh "$keep_headless" --arg kx "$keep_x11" '
    .[] | select(.tag_name | startswith("runtime"))
        | select(.tag_name != $kh and .tag_name != $kx)
        | "\(.id) \(.tag_name)"')

if [ "${#stale[@]}" -eq 0 ]; then
    echo "[runtime-prune] nothing stale to delete (only the latest remains)"
    exit 0
fi

echo "[runtime-prune] deleting ${#stale[@]} stale runtime release(s) + tag(s):"
deleted=0
for line in "${stale[@]}"; do
    id="${line%% *}"
    tag="${line#* }"
    echo "  - $tag (release id $id)"
    if $dry_run; then continue; fi
    # Delete the release (keeps the tag), then the tag. 404 is fine (idempotent).
    curl -sf "${auth[@]}" -X DELETE "$GITEA_API/repos/$GITEA_REPO/releases/$id" >/dev/null 2>&1 || true
    curl -sf "${auth[@]}" -X DELETE "$GITEA_API/repos/$GITEA_REPO/tags/$tag" >/dev/null 2>&1 || true
    deleted=$((deleted + 1))
done

$dry_run || echo "[runtime-prune] pruned $deleted stale runtime cut(s); kept the latest ($keep_hash)"
