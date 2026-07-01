#!/usr/bin/env bash

export CARBONYL_ROOT=$(cd $(dirname -- "$0") && dirname -- $(pwd))

cd "$CARBONYL_ROOT"
source "scripts/env.sh"

version="${1#v}"
[ -n "$version" ] || { echo "Usage: scripts/release.sh <version>" >&2; exit 2; }

npm version "$version" --no-git-tag-version

VERSION="$version" perl -0pi -e '
    s/(\[package\]\s+name = "carbonyl"\s+version = ")[^"]+(")/$1$ENV{VERSION}$2/s
' Cargo.toml

VERSION="$version" perl -0pi -e '
    s/(\[\[package\]\]\s+name = "carbonyl"\s+version = ")[^"]+(")/$1$ENV{VERSION}$2/s
' Cargo.lock

bash "$CARBONYL_ROOT/scripts/verify-release-metadata.sh" "$version"

"$CARBONYL_ROOT/scripts/changelog.sh" --tag "$version"
git add -A .
git commit -m "chore(release): $version"
git tag -a "v$version" -m "chore(release): $version"
