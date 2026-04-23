# Dockerfile.builder — Carbonyl CI builder image
#
# Contains all build dependencies for:
#   - Chromium patches / GN toolchain (ninja, gn, clang, python3, depot_tools)
#   - Rust toolchain (rustup, cargo)
#   - Runtime packaging (tar, strip, curl, jq)
#
# The Chromium source checkout (~30 GB) is NOT baked into this image.
# It lives at a fixed path on the build runner host (e.g. /srv/chromium/src)
# and is bind-mounted into the container by the CI runner.
#
# Usage (manual):
#   docker build -f build/Dockerfile.builder -t roctinam/carbonyl-builder:latest .
#
# CI usage:
#   All CI jobs use `runs-on: titan` — carbonyl builds run exclusively on titan.

FROM ubuntu:22.04

ARG BUILD_DATE
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.title="carbonyl-builder" \
      org.opencontainers.image.description="Carbonyl CI build environment" \
      org.opencontainers.image.source="https://git.integrolabs.net/roctinam/carbonyl"

ENV DEBIAN_FRONTEND=noninteractive

# ── System packages ───────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    # Build essentials
    build-essential \
    python3 python3-pip \
    ninja-build \
    curl wget git \
    # Clang (Chromium uses its own bundled clang, but system clang is a fallback)
    clang lld \
    # Cross-compilation support
    g++-aarch64-linux-gnu libc6-dev-arm64-cross \
    # Chromium code-generation tools (needed during ninja compile)
    # - gperf: Blink CSS/HTML parser hash tables
    # - bison, flex: Blink/V8 parser generators
    # - pkg-config: locates system libraries
    gperf bison flex pkg-config \
    # Chromium build-time + runtime dependencies
    # - libgbm1, libegl1, libgl1: needed at build time when the build
    #   system actually runs tool binaries like v8_context_snapshot_generator
    libasound2 libexpat1 libfontconfig1 libnss3 \
    libdbus-1-dev libglib2.0-dev libnss3-dev libxtst-dev \
    libgbm1 libegl1 libgl1 libxkbcommon0 \
    # Tooling
    jq \
    ca-certificates \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# ── Rust toolchain ────────────────────────────────────────────────────────────
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# Pin Rust to a specific version rather than floating `stable`. The repo
# root also carries a rust-toolchain.toml at the same version; this pin
# in the image keeps image builds reproducible and avoids a first-run
# rustup download when the repo's toolchain file is respected. Bump this
# in lockstep with rust-toolchain.toml.
ARG RUST_VERSION=1.91.0
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y \
        --no-modify-path \
        --default-toolchain "${RUST_VERSION}" \
        --profile minimal \
        --component rustfmt clippy && \
    rustup target add aarch64-unknown-linux-gnu x86_64-unknown-linux-gnu && \
    # Cross-compilation linkers
    echo '[target.aarch64-unknown-linux-gnu]' >> /usr/local/cargo/config.toml && \
    echo 'linker = "aarch64-linux-gnu-gcc"' >> /usr/local/cargo/config.toml && \
    rustc --version && cargo --version && clippy-driver --version

# ── Git safe.directory + CI identity ──────────────────────────────────────────
# The build bind-mounts /chromium/src (and the workspace) into the container
# from the host runner. git refuses to operate on repos it thinks have
# "dubious ownership" when uid(file) != uid(process). Allow any directory
# system-wide inside this image — all git access here is trusted CI.
# Also set a CI identity so `git am` / `git commit` work without nagging.
RUN git config --system --add safe.directory '*' && \
    git config --system user.email 'ci@carbonyl.local' && \
    git config --system user.name 'Carbonyl CI'

# ── Verify tools ──────────────────────────────────────────────────────────────
RUN ninja --version && \
    python3 --version && \
    curl --version | head -1 && \
    jq --version && \
    git --version

WORKDIR /workspace
