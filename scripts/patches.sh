#!/usr/bin/env bash

export CARBONYL_ROOT=$(cd $(dirname -- "$0") && dirname -- "$(pwd)")

source "$CARBONYL_ROOT/scripts/env.sh"

cd "$CHROMIUM_SRC"

# M135 (135.0.7049.84) baseline commits.
# chromium_upstream: set this to the output of `git -C "$CHROMIUM_SRC" rev-parse HEAD`
# after running `bash scripts/gclient.sh sync` for the first time on M135.
chromium_upstream="6c019e56001911b3fd467e03bf68c435924d62f4"  # 135.0.7049.84
skia_upstream="6e445bdea696eb6b6a46681dfc1a63edaa517edb"      # DEPS @ 135.0.7049.84
webrtc_upstream="9e5db68b15087eccd8d2493b4e8539c1657e0f75"    # DEPS @ 135.0.7049.84

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
