# CI/CD Plan — Gitea Actions v3 + Builder Container

**Status**: Implemented. Green as of `build-runtime.yml` run 133 and
`mirror.yml` run 134 on `c751224`.

## Why this doc exists

Carbonyl's build servers are **shared workstations**. Installing Rust toolchains, clang, depot_tools, or Chromium build deps directly on the host pollutes the machine and conflicts with other projects sharing the same worker. Policy: **every CI job runs inside a builder container** so host state stays clean. The fortemi project already operates on this pattern; we mirror it here.

Secondary constraint: the Chromium build is heavy (~150GB source, ~40GB build artifacts, multi-hour rebuilds). It can only run on **titan** (our largest in-house CPU host) and cannot be moved to a generic ephemeral runner.

## Current state

| Piece | Location | Status |
|-------|----------|--------|
| Gitea workflows | `.gitea/workflows/check.yml`, `.gitea/workflows/build-runtime.yml`, `.gitea/workflows/release.yml` | Run on `titan` using the pinned builder image; host toolchains are not required. |
| Builder Dockerfile | `build/Dockerfile.builder` | Published by `build-builder.yml`; consumers pin `.gitea/builder-image-pin`. |
| Builder image publish | `.gitea/workflows/build-builder.yml` | Decoupled from runtime builds. Publishes `latest` + `sha-<short>` to `git.integrolabs.net/roctinam/carbonyl-builder`. |
| Runtime packaging | `scripts/build.sh`, `runtime-push.sh`, `runtime-pull.sh`, `runtime-hash.sh` | `build-runtime.yml` publishes both `headless` and `x11` amd64 runtimes on relevant source changes and manual dispatch. |
| Release publishing | `.gitea/workflows/release.yml` | Tag-driven `v*` release workflow; never rebuilds Chromium, only repackages already-published runtime releases for the tag's runtime hash. |
| GitHub mirror | `.gitea/workflows/mirror.yml` | One-way origin → GitHub sync for `main` and `v*` tags. Uses explicit remote SHA force-with-lease for branch updates. |
| Runner labels in use | `titan` | Single runner. No label segmentation for light vs heavy jobs. |

## Target architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Triggers                                                            │
│   push to main ─┐                                                   │
│   PR ───────────┼─→ check.yml (lint, cargo test)                    │
│                 ├─→ build-runtime.yml (Chromium, gated on patches)  │
│   tag v* ───────┼─→ release.yml (package, publish, mirror)          │
│   Dockerfile.builder change ─→ build-builder.yml                    │
│   push to main ─┐                                                   │
│   tag v* ───────┼─→ mirror.yml (origin → github)                    │
└─────────────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Runner: titan                                                       │
│   Every job runs inside `git.integrolabs.net/roctinam/carbonyl-     │
│   builder:<pinned-tag>` via `container:` directive or `docker run`. │
│   Host state: nothing installed beyond Docker + git + runner.       │
│                                                                     │
│   Bind mounts (for heavy Chromium build only):                      │
│     /srv/chromium/src     → /build/chromium/src      (~150GB)       │
│     /srv/chromium/cache   → /build/chromium/cache    (ccache, etc)  │
└─────────────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Outputs                                                             │
│   Gitea Container Registry:                                         │
│     git.integrolabs.net/roctinam/carbonyl-builder:{latest, sha-*}   │
│   Gitea Releases:                                                   │
│     runtime-<hash>  ← runtime tarballs (input to build-local.sh)    │
│     v0.x.y-*        ← source + packaged runtime for consumers       │
│   GitHub mirror:                                                    │
│     github.com/jmagly/carbonyl  ← main branch + tags                │
│     GitHub Releases (mirrored)  ← release assets duplicated         │
└─────────────────────────────────────────────────────────────────────┘
```

## Workflows

| Workflow | Trigger | Runtime | Purpose |
|----------|---------|---------|---------|
| `build-builder.yml` | Dockerfile.builder change; manual | titan, bare host (Docker only) | Build and push the builder image. Decoupled from runtime builds. |
| `check.yml` | push, PR | titan, inside builder container | cargo fmt + clippy + lib test. Fast feedback on Rust changes. |
| `build-runtime.yml` | runtime-affecting source changes; manual | titan, inside builder container (with bind-mounted Chromium src) | Full Chromium build, runtime hash, tarball upload to Gitea runtime release. Fans out over headless and x11. |
| `release.yml` | `v*` tag push; manual | titan, inside builder container | On tag, pull matching Linux and macOS runtime tarballs by hash, package, create Gitea + GitHub releases with notes. |
| `mirror.yml` | push to main, `v*` tag push | titan, bare host (git only) | Sync origin → github remote. Tags + main. |

## Key design decisions

- **Builder image is the only thing that requires root on the host.** Everything else is container-in-container-less (we don't nest docker, we just bind-mount source). That simplifies `runs-on: titan` while respecting the "no host toolchain" rule.
- **Chromium source checkout lives on the host, not in the container.** 150 GB doesn't fit in an image. Bind-mounted read-write at build time; builder container holds only the toolchain.
- **Runtime tarballs are keyed by `runtime-<hash>`**, computed from `.gclient` + patches + bridge files (see `scripts/runtime-hash.sh`). Consumer-side `build-local.sh` pulls the matching one. Linux runtimes are produced by `build-runtime.yml`; the macOS Apple Silicon runtime is produced on mutsu and published onto the same headless `runtime-<hash>` release as `aarch64-apple-darwin.tgz`.
- **Release artifacts are source-level tags (`v0.x.y`) separate from runtime tags (`runtime-<hash>`).** Source tag points at code + docs; runtime tag points at pre-built binaries. One `v0.x.y` release may reference multiple `runtime-<hash>` assets if re-built for different architectures.
- **GitHub mirror is one-way** (origin → github, never the reverse). Tag pushes replicate. This matches the "push to origin first" convention in top-level `CLAUDE.md`.
- **Host workspace sync is ownership-normalized before rsync.** `build-runtime.yml`
  fixes stale root-owned files under `/srv/carbonyl/` before copying the
  workspace checkout and uses rsync without owner/group preservation. The heavy
  Chromium checkout and depot_tools tree are excluded from this normalization.
- **X11 runtime validation checks two outputs.** `scripts/test-x-mirror.sh`
  captures Carbonyl through a PTY for terminal ANSI output and screenshots the X
  framebuffer; both must pass before publishing the x11 runtime.

## Approval gates (per policy)

Each workflow change is a separate PR with its own review. The issues filed alongside this doc are the proposals for approval. No workflow lands without:

- Review of the `.yml` diff by a maintainer with runner access
- Confirmation that the builder image contains all needed tools (runner dry-run OK)
- Secrets verified in Gitea repo settings before workflow goes live
- `workflow_dispatch` enabled for manual rollback-of-cadence testing

## Secrets inventory

The authoritative inventory + rotation procedure + leak-response
playbook lives in [`docs/ci-secrets.md`](ci-secrets.md). Summary:

| Secret | Used by |
|---|---|
| `BUILD_REPO_TOKEN` | build-builder.yml, build-runtime.yml, check.yml, release.yml |
| `GH_MIRROR_TOKEN` | mirror.yml, release.yml (mirror step) |

Secrets are stored in Gitea repo settings → Actions. Nothing lives on
disk on titan. Any developer with workflow approve permission can see
`secrets.*` references but not values.

## Runner + host state documentation (planned)

A single doc (`docs/ci-runner-titan.md`, filed as an issue) capturing:
- What's expected on titan: Docker daemon, gitea-runner user, passwordless sudo scoped to Docker only
- Chromium source checkout location, size, last-sync date, invalidation on m-version bump
- ccache / ninja output location, size caps, cleanup policy
- Debug steps: how to SSH into a running job's container, how to capture a failing build's artifacts

## Resolved decisions (2026-04-17)

1. **Runner label**: single `titan` label. Light checks queue behind Chromium builds; that's acceptable given current cadence. Revisit only if PR feedback latency becomes a problem.
2. **Builder image cadence**: rebuild on Dockerfile change (deterministic). No weekly rebuilds.
3. **Builder image tag consumed by downstream workflows**: `sha-<7chars>` pinned, **never `latest`**. Downstream workflows must pin the exact SHA; promoting a new image to production is an explicit, reviewable action (edit the pin in one of #50/#51/#52's workflow files).
4. **GHCR mirror of builder image**: **Phase 2, yes** — add `ghcr.io/jmagly/carbonyl-builder` mirror once Phase 1 (Gitea-only) is green. Requires new `GHCR_TOKEN` secret; configured when ready to test. Handled in #49 as a follow-up step.
5. **Secret rotation cadence**: 1 year. Internal key-management service is planned; once it lands the rotation story moves there and the doc in #54 becomes a pointer.
6. **Release tarball signing**: deferred to post-stability (out of scope for this migration).

## Filed issues

See the tracker for detailed acceptance criteria on each. Ordered by dependency:

- Builder image publication workflow — gates everything else
- Migrate `check.yml` to builder container — proves the pattern on the lightest workflow
- Migrate `build-runtime.yml` to builder container — proves the pattern under load
- Release workflow on tag push — publishes the work we've already tagged
- GitHub mirror sync workflow — maintains parity with the external audience
- Secrets and tokens inventory + rotation doc — audit artifact for compliance
- Runner and host state documentation — operational knowledge for titan

Each is independently reviewable and approveable. No single mega-PR.
