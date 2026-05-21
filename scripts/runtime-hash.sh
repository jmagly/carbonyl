#!/usr/bin/env bash
# runtime-hash.sh — Compute the aggregate hash that keys runtime release tags.
#
# Inputs:
#   - chromium/.gclient                      (Chromium version pin)
#   - chromium/patches/*/*.patch             (all carbonyl Chromium patches)
#   - src/browser/*.{cc,h,gn,mojom}          (injected C++ + Mojo + GN)
#   - src/**/*.rs (find, excludes target/)   (Rust libcarbonyl sources)
#   - Cargo.toml, Cargo.lock                 (Rust dep state)
#   - rust-toolchain.toml                    (Rust toolchain pin)
#
# Rust files were added per #92 — they affect the runtime binary
# (libcarbonyl.so is loaded at process start by the patched headless_shell)
# but were previously excluded, causing pure-libcarbonyl fixes to share a
# release tag with the prior build and surfacing as "already installed"
# to consumers running runtime-pull.sh.

export CARBONYL_ROOT=$(cd $(dirname -- "$0") && dirname -- $(pwd))

cd "$CARBONYL_ROOT"
source "scripts/env.sh"

sha=""

# C++ / patch / GN inputs (historical hash inputs — order preserved)
for file in chromium/.gclient chromium/patches/*/*.patch src/browser/*.{cc,h,gn,mojom}; do
    [ -e "$file" ] || continue
    file_sha=$(cat "$file" | openssl sha256)
    sha+="${file_sha: -64} ${file}"$'\n'
done

# Rust source tree under src/ (excludes build artifacts and target/).
# `-print0` + `read -d ''` keeps spaces safe; `sort` stabilises across hosts.
while IFS= read -r -d '' file; do
    file_sha=$(cat "$file" | openssl sha256)
    sha+="${file_sha: -64} ${file}"$'\n'
done < <(find src -type f -name '*.rs' -print0 | sort -z)

# Rust dep + toolchain manifests
for file in Cargo.toml Cargo.lock rust-toolchain.toml; do
    [ -e "$file" ] || continue
    file_sha=$(cat "$file" | openssl sha256)
    sha+="${file_sha: -64} ${file}"$'\n'
done

hash=$(echo "$sha" | sort | openssl sha256)

echo -n "${hash: -16}"
