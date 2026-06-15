# ADR-004: Maintained runtime container image on GHCR

- **Status:** Accepted
- **Date:** 2026-06-14
- **Issue:** roctinam/carbonyl#132
- **Supersedes:** none
- **Related:** #129 (native install packages, ADR-003), #116 (arm64-linux runtime), #52/#53 (release + mirror), [jmagly/carbonyl#1](https://github.com/jmagly/carbonyl/pull/1) (community PR — entrypoint / zoom / tini / x11 adapted from @eSlider)

## Context

The only Carbonyl container image users can pull today is upstream
`fathyb/carbonyl` on Docker Hub — M111-era, unmaintained since 2023. This fork
ships runtime tarballs, an npm package, and native install packages (ADR-003),
but no maintained image. A container is the lowest-friction way to run a
terminal browser on a host you don't want to install libraries on, and the
obvious one-liner is `docker run --rm -ti <image> <url>`.

The runtime is the same relocatable payload the installers wrap, and we already
build and validate a `.deb` for the headless `x86_64` runtime on titan (#129).

## Reasoning

1. **Problem analysis.** Provide a maintained image under the fork's namespace
   so `docker run ghcr.io/jmagly/carbonyl <url>` runs the current runtime. The
   payload exists per release; the work is image assembly + a publish path.
2. **Constraint identification.** (a) Registry: the request is GHCR under the
   `jmagly` namespace. (b) ghcr push needs a `write:packages` token — the
   existing `GH_MIRROR_TOKEN` is `contents:write` only, so a new credential is
   required. (c) A publish failure must never block a release. (d) Runtime libs
   must resolve in-container exactly as they do for installed users. (e) Only
   `x86_64` linux runtime exists today (arm64 is #116); macOS is not a container
   target.
3. **Alternatives considered.**
   - *Image contents:* hand-pick `apt` packages + copy the payload, **vs.
     install the published `.deb`**. Installing the `.deb` chosen — the curated
     dependency list lives in exactly one place (`scripts/package-linux.sh`),
     and the container's library set becomes byte-identical to what the `.deb`
     install smoke already validates. "The container installs the same package
     users install" is a strong correctness property.
   - *Base image:* `debian:*-slim` vs **`ubuntu:24.04`**. Ubuntu 24.04 chosen —
     it is the distro the `.deb` depends list (`libasound2t64`, …) was validated
     against in #129.
   - *Where it runs:* fold into `release.yml` vs **a separate workflow**.
     Separate (`publish-image.yml`) chosen — a GHCR outage or a missing
     `GHCR_TOKEN` then cannot fail a release. It is the same isolation rationale
     as keeping the macOS gate non-fatal in `release.yml`.
   - *Registry:* GHCR (as requested) now; a Gitea container-registry mirror is a
     trivial later add (the builder image already lives there) but out of scope.
4. **Decision rationale.** A host-agnostic `scripts/package-image.sh` consumes a
   payload dir + version, builds the `.deb` via `package-linux.sh`, and produces
   an `ubuntu:24.04` image that `apt-get install`s it — so the same code path
   runs locally (test/debug) and in CI. The image runs as a non-root user with
   `--no-sandbox --disable-dev-shm-usage` (no namespace sandbox / tiny `/dev/shm`
   in containers).
5. **Consequence assessment.** Users get a maintained `docker run` one-liner.
   The pipeline grows one isolated workflow and one new secret. The first push
   creates a *private* package — an operator must flip it public for anonymous
   `docker pull`. arm64 is absent until #116.

## Decision

1. **Registry / name:** `ghcr.io/jmagly/carbonyl`.
2. **Platforms / variants:** `linux/amd64`. **headless** → `:<version>` (+ `:latest`)
   and **x11** → `:<version>-x11` (best-effort — skipped if the x11 runtime is
   absent, never fails the run). arm64 follows the arm64-linux runtime (#116).
3. **Image contents:** `ubuntu:24.04` + the published `.deb` (dependency source of
   truth, ADR-003) + **`ca-certificates`** (TLS roots — required for HTTPS) +
   **`tini`** (PID 1 signal/zombie handling). A small `build/docker-entrypoint.sh`
   sets container-safe terminal env (`TERM`/`COLORTERM`/`LANG`), disables dbus,
   sets `CARBONYL_ENV_SHELL_MODE`, adds `--disable-gpu`, and normalizes `--zoom`
   (default `67` to cancel the pre-#100 1.5× internal zoom → ~100% effective).
   Non-root `carbonyl` user; `tini` as PID 1 with `STOPSIGNAL SIGINT`. The
   terminal/zoom/tini hardening is adapted from
   [jmagly/carbonyl#1](https://github.com/jmagly/carbonyl/pull/1) (@eSlider),
   re-pointed at the `.deb` launcher.
4. **Build path:** `build/Dockerfile.runtime` + `scripts/package-image.sh`,
   reused locally and by CI.
5. **Publish:** `.gitea/workflows/publish-image.yml` on `v*` tag /
   `workflow_dispatch`, on titan, isolated from `release.yml`; no-ops with a
   warning when `GHCR_TOKEN` is absent.
6. **Auth:** new `GHCR_TOKEN` secret — a `jmagly` PAT with `write:packages` on
   the `ghcr.io/jmagly` namespace. Documented in `docs/ci-secrets.md`.

## Consequences

- **Positive:** maintained `docker run --rm -ti ghcr.io/jmagly/carbonyl <url>`;
  container libraries match the validated `.deb`; correct HTTPS (ca-certificates)
  and ~100% terminal rendering (zoom/`TERM`); clean signal handling (tini);
  headless + x11 variants; publish isolated from releases; one script path local
  and in CI.
- **Negative / accepted:** a new `write:packages` secret to provision and
  rotate; the first published package is private until an operator makes it
  public; image is `amd64`-only until #116; the `--zoom=67` default is tied to
  the pre-#100 1.5× multiplier and must move to `100` once runtimes drop it.
- **Follow-ups:** arm64 / multi-arch manifest once #116 lands; build-layer
  caching (registry/gha) for faster rebuilds; optional Gitea container-registry
  mirror; image signing / attestation (cosign), deferred consistent with
  `docs/ci-secrets.md`.
