#!/usr/bin/env bash
# runtime-hash.sh — Compute the aggregate hash that keys runtime release tags.
#
# Inputs:
#   - chromium/.gclient                      (Chromium version pin)
#   - chromium/patches/*/*.patch             (all carbonyl Chromium patches)
#   - src/**/*.{cc,h,gn,mojom}               (injected C++ + Mojo + GN)
#   - src/**/*.rs (find, excludes target/)   (Rust libcarbonyl sources)
#   - Cargo.toml, Cargo.lock                 (Rust dep state)
#   - rust-toolchain.toml                    (Rust toolchain pin)
#
# Rust files were added per #92 — they affect the runtime binary
# (libcarbonyl.so is loaded at process start by the patched headless_shell)
# but were previously excluded, causing pure-libcarbonyl fixes to share a
# release tag with the prior build and surfacing as "already installed"
# to consumers running runtime-pull.sh.

CARBONYL_ROOT=$(cd "$(dirname -- "$0")/.." && pwd)
export CARBONYL_ROOT

cd "$CARBONYL_ROOT" || exit 1
# shellcheck source=scripts/env.sh
source "scripts/env.sh"

sha=""

# Chromium pin and patch inputs.
for file in chromium/.gclient chromium/patches/*/*.patch; do
    [ -e "$file" ] || continue
    file_sha=$(openssl sha256 < "$file")
    sha+="${file_sha: -64} ${file}"$'\n'
done

# C++ / Mojo / GN sources under every Carbonyl Chromium integration subtree.
# This includes src/extensions; limiting the hash to src/browser would allow a
# different runtime binary to reuse an existing release tag.
while IFS= read -r -d '' file; do
    file_sha=$(openssl sha256 < "$file")
    sha+="${file_sha: -64} ${file}"$'\n'
done < <(find src -type f \
    \( -name '*.cc' -o -name '*.h' -o -name '*.gn' -o -name '*.mojom' \) \
    -print0 | sort -z)

# Rust source tree under src/ (excludes build artifacts and target/).
# `-print0` + `read -d ''` keeps spaces safe; `sort` stabilises across hosts.
while IFS= read -r -d '' file; do
    file_sha=$(openssl sha256 < "$file")
    sha+="${file_sha: -64} ${file}"$'\n'
done < <(find src -type f -name '*.rs' -print0 | sort -z)

# Rust dep + toolchain manifests
for file in Cargo.toml Cargo.lock rust-toolchain.toml; do
    [ -e "$file" ] || continue
    file_sha=$(openssl sha256 < "$file")
    sha+="${file_sha: -64} ${file}"$'\n'
done

hash=$(echo "$sha" | sort | openssl sha256)

echo -n "${hash: -16}"
