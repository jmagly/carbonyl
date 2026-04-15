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
    echo "Stashing Chromium changes.."
    git add -A .
    git stash

    echo "Applying Chromium patches.."
    git checkout "$chromium_upstream"
    git am --committer-date-is-author-date "$CARBONYL_ROOT/chromium/patches/chromium"/*
    "$CARBONYL_ROOT/scripts/restore-mtime.sh" "$chromium_upstream"

    echo "Stashing Skia changes.."
    cd "$CHROMIUM_SRC/third_party/skia"
    git add -A .
    git stash

    echo "Applying Skia patches.."
    git checkout "$skia_upstream"
    git am --committer-date-is-author-date "$CARBONYL_ROOT/chromium/patches/skia"/*
    "$CARBONYL_ROOT/scripts/restore-mtime.sh" "$skia_upstream"

    echo "Stashing WebRTC changes.."
    cd "$CHROMIUM_SRC/third_party/webrtc"
    git add -A .
    git stash

    echo "Applying WebRTC patches.."
    git checkout "$webrtc_upstream"
    git am --committer-date-is-author-date "$CARBONYL_ROOT/chromium/patches/webrtc"/*
    "$CARBONYL_ROOT/scripts/restore-mtime.sh" "$webrtc_upstream"

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
