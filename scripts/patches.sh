#!/usr/bin/env bash

export CARBONYL_ROOT=$(cd $(dirname -- "$0") && dirname -- "$(pwd)")

source "$CARBONYL_ROOT/scripts/env.sh"

cd "$CHROMIUM_SRC"

# M147 (147.0.7727.94) baseline commits.
# chromium_upstream: set this to the output of `git -C "$CHROMIUM_SRC" rev-parse HEAD`
# after running `bash scripts/gclient.sh sync` for the target version.
chromium_upstream="be35d570111fa75402da99a722251d8af5ee5990"  # 147.0.7727.94
skia_upstream="d203629ce869dbb142ca186c7da60a97cfb1550d"      # DEPS @ 147.0.7727.94
webrtc_upstream="9179833d210d105aede5d4ec516734a6bd1ef2e8"    # DEPS @ 147.0.7727.94

if [[ "$1" == "apply" ]]; then
    # Force-reset each repo to its upstream baseline. The old
    # "git add -A . && git stash" approach didn't handle Chromium's
    # nested/embedded git repos under third_party (not submodules; not
    # gitignored; their own .git dirs). CI has no WIP to protect, and
    # interrupted runs left embedded-repo entries in the index that
    # blocked subsequent `git am` calls with "Dirty index" errors.

    reset_and_apply() {
        local repo_path="$1"
        local upstream_sha="$2"
        local patches_dir="$3"

        echo "Resetting $repo_path to $upstream_sha.."
        cd "$repo_path"
        # Abort any stalled git-am/rebase from interrupted prior runs.
        git am --abort >/dev/null 2>&1 || true
        git rebase --abort >/dev/null 2>&1 || true
        # Force-move to upstream; resets index + working tree to match.
        # Doesn't touch untracked files (including embedded third_party
        # repos on disk), which is what we want — they stay available for
        # the build but aren't considered part of any patching operation.
        git reset --hard "$upstream_sha"

        echo "Applying patches from $patches_dir.."
        git am --committer-date-is-author-date "$patches_dir"/*

        "$CARBONYL_ROOT/scripts/restore-mtime.sh" "$upstream_sha"
    }

    reset_and_apply "$CHROMIUM_SRC"                   "$chromium_upstream" "$CARBONYL_ROOT/chromium/patches/chromium"
    reset_and_apply "$CHROMIUM_SRC/third_party/skia"  "$skia_upstream"     "$CARBONYL_ROOT/chromium/patches/skia"
    reset_and_apply "$CHROMIUM_SRC/third_party/webrtc" "$webrtc_upstream"  "$CARBONYL_ROOT/chromium/patches/webrtc"

    echo "Patches successfully applied"
elif [[ "$1" == "save" ]]; then
    if [[ -d carbonyl ]]; then
        git add -A carbonyl
    fi

    echo "Updating Chromium patches.."
    rm -rf "$CARBONYL_ROOT/chromium/patches/chromium"
    git format-patch --no-signature --output-directory "$CARBONYL_ROOT/chromium/patches/chromium" "$chromium_upstream"

    echo "Updating Skia patches.."
    cd "$CHROMIUM_SRC/third_party/skia"
    rm -rf "$CARBONYL_ROOT/chromium/patches/skia"
    git format-patch --no-signature --output-directory "$CARBONYL_ROOT/chromium/patches/skia" "$skia_upstream"

    echo "Updating WebRTC patches.."
    cd "$CHROMIUM_SRC/third_party/webrtc"
    rm -rf "$CARBONYL_ROOT/chromium/patches/webrtc"
    git format-patch --no-signature --output-directory "$CARBONYL_ROOT/chromium/patches/webrtc" "$webrtc_upstream"

    echo "Patches successfully updated"
else
    echo "Unknown argument: $1"

    exit 2
fi
