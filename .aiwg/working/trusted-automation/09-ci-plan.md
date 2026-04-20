# CI Plan — Trusted Automation Initiative

Complements `docs/ci-cd-plan.md` (Carbonyl core Chromium build pipeline). That doc covers the base project's build/release/mirror workflows. This doc covers the **initiative-specific** CI surface across four repos.

## Scope

Initiative CI must cover:

1. Per-phase test suite execution (Layers 1–4+ as they come online)
2. Cross-repo coordination — QA waits for matching Carbonyl runtime + agent build
3. `jmagly/wreq` fork lifecycle — sync, build, tag, security scan
4. Fingerprint-corpus refresh pipeline (Phase 3A.4)
5. Per-persona observed-fingerprint regression (Phase 3D nightly)
6. Secrets handling for QA repo (throwaway credentials, private repo)

## Current per-repo CI state

| Repo | Workflows | Runner | Status |
|------|-----------|--------|--------|
| `carbonyl` | `check.yml`, `build-runtime.yml` | titan | Host-pollution pattern; migration to builder container is tracked separately in `docs/ci-cd-plan.md` |
| `carbonyl-agent` | None visible at planning time | — | Greenfield; this plan proposes the inaugural set |
| `carbonyl-agent-qa` | None | — | Greenfield; private repo |
| `carbonyl-fleet` | None visible | — | Greenfield; Phase 4 scope |
| `wreq` (roctinam/wreq, Gitea) | None | titan or generic | **New**: Gitea-primary fork; CI inaugural set proposed below |
| `carbonyl-fingerprint-corpus` (roctinam, Gitea, private) | None | generic | **New**: data repo; corpus refresh bot writes here; consumed by carbonyl-agent at build |

## Target workflow inventory by repo

### `carbonyl`

Mostly inherited from `docs/ci-cd-plan.md`. Additions for the initiative:

| Workflow | Trigger | Purpose | Phase |
|----------|---------|---------|-------|
| `check.yml` (existing, migrated) | PR, push main | Rust fmt + clippy + tests | 1+ |
| `build-runtime.yml` (existing, migrated) | patch change; manual | Chromium build + runtime tarball | 1+ |
| `patch-audit.yml` (**NEW**) | patch file change in `chromium/patches/` | Validates each patch applies cleanly on pinned Chromium; runs `scripts/patches.sh apply --dry-run` | 2 |
| `initiative-smoke.yml` (**NEW**) | push main | Spin up Carbonyl x11 build inside `carbonyl-agent-qa-runner` container on `DISPLAY=:99`; confirm uinput→Xorg→Chromium path alive and `scrot` returns a non-blank framebuffer | 1+ |

### `carbonyl-agent`

All greenfield. Proposed inaugural set:

| Workflow | Trigger | Purpose | Phase |
|----------|---------|---------|-------|
| `check.yml` | PR, push main | Python `ruff` + `mypy` + `pytest` unit; Rust `cargo test` for humanization crate | 1+ |
| `wreq-pin-audit.yml` (**NEW**) | weekly cron + manual | Compare pinned `roctinam/wreq` tag against the fork's latest `carbonyl.*` release; emit issue on drift | 3+ |
| `corpus-refresh.yml` (**NEW**) | weekly cron + on new Chrome stable release | Detect stable Chrome via `chromiumdash` / omahaproxy; capture reference JA4/UA-CH via `tls.peet.ws`; open PR to update corpus | 3+ |
| `persona-lint.yml` (**NEW**) | push touching personas | Validate every persona passes the registry consistency validator before merge | 3+ |
| `integration.yml` (**NEW**) | push main + nightly | Spawn Carbonyl+agent, drive against local fixtures; uses a matching `carbonyl` runtime tarball (pulled via `build-local.sh` runtime-hash matching) | 1+ |

### `carbonyl-agent-qa` (private)

All greenfield. Note: this repo exercises network-dependent tests with throwaway credentials. Private repo + restricted runner labels.

| Workflow | Trigger | Purpose | Phase |
|----------|---------|---------|-------|
| `qa-smoke.yml` | PR, push main | Unit-ish: HTTP server fixture + spawn Carbonyl+agent; local-page assertions | 1+ |
| `qa-layer1.yml` (**NEW**) | nightly | Layer 1 (trusted input) full probe suite against local pages | 1+ |
| `qa-layer2-3.yml` (**NEW**) | nightly | Automation + environment fingerprint probes (bot.sannysoft.com, creepjs, pixelscan) | 2+ |
| `qa-layer4.yml` (**NEW**) | nightly | Behavioral statistical tests (KS test on keystroke timing, Fitts fit, overshoot rate) | 2+ |
| `qa-layer5.yml` (**NEW**) | nightly | Observed JA4 + JA4H + H2 Akamai fingerprint capture per persona; declared-vs-observed assertion | 3+ |
| `qa-reference-sites.yml` (**NEW**) | nightly + on-demand | Turnstile + DataDome demo + x.com login flow (gated on CI secrets) | 2+ |
| `qa-regression.yml` (**NEW**) | nightly, depends on above | Compare results to golden; alert on drop in pass rate | 2+ |

### `carbonyl-fleet`

Phase 4. Inherits `carbonyl-agent` workflow patterns plus:

| Workflow | Trigger | Purpose | Phase |
|----------|---------|---------|-------|
| `fleet-multi-instance.yml` | push main + nightly | N=10 concurrent Carbonyl spawns; per-instance QA assertions via uinput namespacing | 4 |

### `roctinam/wreq` (Gitea-primary fork, public)

See the dedicated §"roctinam/wreq (Gitea primary) fork lifecycle" section below for the full branching policy and sync flow. Workflows (all on Gitea; no CI lives on the GitHub mirror):

| Workflow | Trigger | Purpose | Phase |
|----------|---------|---------|-------|
| `upstream-sync.yml` | weekly cron + manual | Rebase `main` onto `0x676e67/wreq` upstream; push to origin (Gitea) | 3+ |
| `build.yml` | push, PR | `cargo test --all-features` inside `wreq-ci` builder container | 3+ |
| `security-scan.yml` | daily cron | `cargo-audit`, RUSTSEC alerts; opens issue on findings | 3+ |
| `release.yml` | tag `v*-carbonyl.*` | Gitea release; triggers mirror.yml to sync to GitHub release | 3+ |
| `mirror.yml` | push main + tag push | One-way origin (Gitea) → `github.com/jmagly/wreq` | 3+ |

### `roctinam/carbonyl-fingerprint-corpus` (Gitea, private)

Data repo, not a build target. CI is light — validate corpus integrity and coordinate downstream pin bumps. `roctibot` is a write collaborator so the refresh pipeline running in `carbonyl-agent` can open PRs here.

| Workflow | Trigger | Purpose | Phase |
|----------|---------|---------|-------|
| `validate.yml` | push, PR | Schema validation on corpus files; lint personas; assert no persona regresses the consistency validator | 3+ |
| `notify-consumers.yml` | tag push `corpus-*` | Open PR in `carbonyl-agent` bumping the corpus pin | 3+ |

## Cross-repo coordination

### Problem

QA tests in `carbonyl-agent-qa` need specific versions of both:
- `carbonyl` runtime (matching Chromium patches + FFI ABI)
- `carbonyl-agent` SDK (matching persona schema + wreq pin)

Running `carbonyl-agent-qa` against stale builds produces false regressions.

### Approach

**Compatibility pin file**: `carbonyl-agent-qa/config/compat.toml` declares:

```toml
[compat]
carbonyl_runtime_hash = "abc123..."        # matches scripts/runtime-hash.sh output
carbonyl_agent_ref    = "v0.3.1"           # git tag or commit SHA
fingerprint_crate_ref = "v0.2.0"           # carbonyl-fingerprint crate version
```

Bumped manually when a dependent ships a breaking change; automated PR when all three repos hit a tagged release simultaneously.

**Trigger chain**:
- `carbonyl` tag push → release workflow uploads runtime tarball + updates `latest-runtime-hash` marker
- `carbonyl-agent` tag push → release workflow publishes package + updates `latest-agent-ref` marker
- `carbonyl-agent-qa` nightly fetches both markers, composes the test environment, runs the full corpus

**Optional**: a dispatcher workflow in a fifth control repo (or in the agent repo) listens for tag pushes from carbonyl/agent and opens compat-bump PRs automatically.

## `roctinam/wreq` (Gitea primary) fork lifecycle

### Branching policy

- **`main`** tracks `0x676e67/wreq` (upstream) `main`. Rebased, not merged, to keep history flat.
- **`carbonyl/*`** named branches carry local patches (Chrome version adds, profile tweaks, security backports).
- **Tags**: `vX.Y.Z-carbonyl.N` where `X.Y.Z` is the upstream release and `N` increments for our patch series. Example: `v6.0.0-rc.28-carbonyl.1`.

### Sync workflow

```
┌──────────────────────────────────────────────────────────────────┐
│ upstream github.com/0x676e67/wreq       (fetch-only)             │
└───────────────┬──────────────────────────────────────────────────┘
                │ fetch (weekly cron + on-demand for CVE)
                ▼
┌──────────────────────────────────────────────────────────────────┐
│ origin: git.integrolabs.net/roctinam/wreq  main  (Gitea primary) │
│   rebased tracker; CI runs here                                  │
└───────────────┬──────────────────────────────────────────────────┘
                │ rebase (quarterly or on-demand) + mirror push
                │
                ├─────→ github.com/jmagly/wreq  (publish mirror)
                │
                ▼
┌──────────────────────────────────────────────────────────────────┐
│ roctinam/wreq  branch: carbonyl/carbonyl                          │
│   ↳ tag v6.0.0-rc.28-carbonyl.1 when ready for downstream bump    │
│   ↳ Gitea release + mirrored GitHub release                       │
└───────────────┬──────────────────────────────────────────────────┘
                │ pin bump PR
                ▼
┌──────────────────────────────────────────────────────────────────┐
│ carbonyl-agent  Cargo.toml                                        │
│   wreq = { git = "https://git.integrolabs.net/roctinam/wreq",     │
│            tag = "v6.0.0-rc.28-carbonyl.1" }                      │
│                                                                   │
│   (consumers who can't reach Gitea use the GitHub mirror URL      │
│    as a fallback; Cargo's `git` key supports any https URL)       │
└──────────────────────────────────────────────────────────────────┘
```

### Workflow in the fork repo

`.github/workflows/` (since the fork lives on GitHub, not Gitea):

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `upstream-sync.yml` | weekly cron + manual | `git fetch upstream; git rebase upstream/main main; push origin main --force-with-lease` on a protected schedule; produce a PR if conflicts |
| `build.yml` | push, PR | `cargo test --all-features`; asserts our `carbonyl/*` branches still build |
| `security-scan.yml` | daily cron | `cargo-audit` + `cargo-deny`; alert on RUSTSEC advisories affecting BoringSSL or h2 |
| `release.yml` | tag `v*-carbonyl.*` | GitHub release with a short changelog describing local patches |

### Security policy for the fork

- Never `--force` push `main` except via `--force-with-lease` in the rebase workflow with signed commits
- `carbonyl/*` branches are protected; changes via PR only, with one reviewer
- CVE response SLA: BoringSSL/h2 CVE → cherry-pick to `carbonyl/carbonyl` + tag within 72h
- Abandon criterion: if upstream goes silent for >6 months AND wreq ecosystem proves burdensome to maintain alone, evaluate migration to `tls-client` (cgo fallback) or `cloudflare/boring` (owned-profile path). ADR-005 documents the fallback.

## Corpus refresh pipeline (Phase 3A.4)

```
┌─────────────────────────────────────────────────────────────┐
│ Weekly cron in carbonyl-agent                               │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. Detect stable Chrome via chromiumdash/omahaproxy API     │
│    currrent_stable = "147.0.7727.94" (example)              │
└─────────────────┬───────────────────────────────────────────┘
                  │ if current_stable > last_corpus_chrome
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Capture reference fingerprints                           │
│    - JA4/JA4H via tls.peet.ws                               │
│    - UA-CH full version list via Chrome's own site          │
│    - H2 Akamai via http2.pro                                │
│    - WebGL/plugins expected values via Chromium source      │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Open PR updating corpus with new Chrome tuple            │
│    - fingerprint_corpus/chrome-147.toml (new)               │
│    - Mark chrome-146 personas as "stale-1-major"            │
│    - Bump wreq pin if wreq-util has Chrome 147 profile      │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. CI runs persona-lint against new corpus                  │
│    - Fail if any existing persona breaks validation         │
│    - Assignee reviews and merges                            │
└─────────────────────────────────────────────────────────────┘
```

## Runner + container strategy

### The rule: every job runs inside a builder container

All CI across the initiative inherits the **no-host-toolchain** discipline established in `docs/ci-cd-plan.md` for carbonyl core, which itself follows the pattern set by the **Fortemi** project (`Fortemi/fortemi` on Gitea). Rationale: our runners — especially `titan` — are shared hosts. Installing Rust toolchains, clang, Python environments, or Chromium build deps directly on the host pollutes it and conflicts with other projects sharing the same worker.

**Policy**: every CI job is launched inside a pinned builder image pulled from the Gitea Container Registry. Host state beyond Docker + git + the runner daemon is forbidden.

Per-repo builder images:

| Repo | Builder image | Contents | Notes |
|------|---------------|----------|-------|
| `carbonyl` | `git.integrolabs.net/roctinam/carbonyl-builder:sha-<pin>` | Ubuntu + depot_tools + Rust + clang | Existing; see `docs/ci-cd-plan.md` |
| `carbonyl-agent` | `git.integrolabs.net/roctinam/carbonyl-agent-ci:sha-<pin>` | Python + Rust + minimal runtime deps | **New**; no X |
| `carbonyl-agent-qa` | `git.integrolabs.net/roctinam/carbonyl-agent-qa-runner:sha-<pin>` | Python + **Xorg (dummy + modesetting drivers)** + `python-uinput` + `scrot`/`ffmpeg`/`x11vnc` + Carbonyl x11 runtime + persistent profile volume | **New**; container entrypoint starts Xorg on `:99`, respects `CARBONYL_GPU_MODE` env |
| `wreq` (roctinam/wreq) | `git.integrolabs.net/roctinam/wreq-ci:sha-<pin>` | Rust + BoringSSL build deps | **New** |
| `carbonyl-fingerprint-corpus` | `git.integrolabs.net/roctinam/carbonyl-agent-ci:sha-<pin>` | Reuses agent-ci image for corpus validation | **Shared** |

Each builder image has its own `build-builder.yml` workflow following the Fortemi pattern: triggered on Dockerfile change, publishes `latest` + `sha-<7chars>`, downstream workflows pin to the SHA tag (never `latest`). Promotion is an explicit edit of the pin in consumer workflows.

### carbonyl core (inherited)

Single `titan` runner, builder container pattern per `docs/ci-cd-plan.md`. No changes.

### carbonyl-agent, carbonyl-agent-qa

Per ADR-002 rev 2, integration and reference-site containers bundle **Xorg** (with both `dummy` and `modesetting` drivers installed so the entrypoint can pick at runtime) and pass `/dev/uinput` through. `CARBONYL_GPU_MODE=auto|cpu|gpu` env var picks the Xorg driver + Chromium GL backend; `auto` detects `/dev/dri/card0` presence.

| Job class | Runner | Container | Notes |
|-----------|--------|-----------|-------|
| Python/Rust unit tests | generic (any capacity) | `carbonyl-agent-ci` builder (lightweight; no X) | No Chromium deps; fast |
| Integration with Carbonyl runtime | titan | `carbonyl-agent-qa-runner` (Xorg + `dummy`/`modesetting` + uinput + capture tools + Carbonyl x11 build) | Heavier; `CARBONYL_GPU_MODE=cpu` in CI for determinism |
| Reference-site QA | titan | same `carbonyl-agent-qa-runner` | Nightly; needs persistent profile volume for aged personas; `scrot`/`ffmpeg` capture alongside terminal render |
| Persona capture (tls.peet.ws, creepjs fetch) | generic | `carbonyl-agent-ci` + Carbonyl runtime | Nightly; outbound-internet required |

#### `carbonyl-agent-qa-runner` container contents

- Ubuntu base (match carbonyl-builder OS version)
- Xorg + `xserver-xorg-video-dummy` + `xserver-xorg-video-modesetting` + input drivers
- `uinput` kernel module requires no in-container install — comes from host via `--device=/dev/uinput`
- Capture tooling: `scrot`, `ffmpeg`, optionally `x11vnc` for remote-display streaming
- Carbonyl x11 build + agent SDK + `python-uinput`
- Entrypoint: `/usr/local/bin/carbonyl-agent-qa-entrypoint` picks driver + GL backend per `CARBONYL_GPU_MODE`, starts Xorg on `:99`, exports `DISPLAY=:99`, execs the job command

#### Docker run patterns

```bash
# CPU (CI default; works anywhere)
docker run --rm --device=/dev/uinput --group-add input \
  -e CARBONYL_GPU_MODE=cpu \
  carbonyl-agent-qa-runner  pytest tests/layer1

# GPU operator opt-in
docker run --rm --device=/dev/uinput --group-add input \
  --device=/dev/dri --gpus all \
  -e CARBONYL_GPU_MODE=gpu \
  carbonyl-agent-qa-runner  pytest tests/layer1

# Auto (tries GPU, falls back to CPU based on /dev/dri presence)
docker run --rm --device=/dev/uinput --group-add input \
  --device=/dev/dri:/dev/dri \
  carbonyl-agent-qa-runner  pytest tests/layer1
```

### carbonyl-fleet (Phase 4)

N=10 concurrent Carbonyl instances require a host with sufficient memory + `/dev/uinput` per-instance namespacing. Likely titan or a dedicated fleet-testing host (TBD Phase 4 planning).

## Secrets inventory (initiative-specific)

| Secret | Scope | Used by | Notes |
|--------|-------|---------|-------|
| `WREQ_GITHUB_MIRROR_TOKEN` | GitHub PAT with write on `jmagly/wreq` | `mirror.yml` on `roctinam/wreq` (Gitea → GitHub push) | 1y; scoped to the mirror repo only |
| `WREQ_SYNC_TOKEN` | Gitea PAT with write on `roctinam/wreq` | `upstream-sync.yml` rebase-and-push | 1y |
| `QA_THROWAWAY_X_CREDS` | Scoped to `carbonyl-agent-qa` only | `qa-reference-sites.yml` x.com flow | Rotated per quarter; credentials for throwaway test account |
| `QA_THROWAWAY_CF_CREDS` | Same | Cloudflare Turnstile demo runs | May not be needed; Turnstile demo is open |
| `FINGERPRINT_CAPTURE_USER_AGENT` | carbonyl-agent | `corpus-refresh.yml` | Identifies our refresh bot to fingerprint sites (operational courtesy) |
| `BUILD_REPO_TOKEN` (existing) | Gitea PAT | Cross-repo tag coordination; existing | Unchanged |

Throwaway credentials are stored in Gitea secrets on `carbonyl-agent-qa` only. No credential reuse across repos. Rotation documented in a `docs/secrets.md` in the QA repo.

## Approval gates (per-phase CI additions)

Each new workflow lands as its own PR in the relevant repo, following the pattern established in `docs/ci-cd-plan.md`:

- Review `.yml` diff by a maintainer with runner access
- Confirm builder image/container has required tools (dry-run OK)
- Secrets verified in repo settings before workflow goes live
- `workflow_dispatch` enabled for manual rollback-of-cadence testing

Initiative-specific gates:

- **Phase 1 entry**: `check.yml` in carbonyl-agent + `qa-smoke.yml` in carbonyl-agent-qa must be green
- **Phase 2 entry**: Phase 1 gate + `patch-audit.yml` in carbonyl (every Chromium patch applies cleanly)
- **Phase 3 entry**: Phase 2 gate + `wreq-pin-audit.yml` passing + `persona-lint.yml` seeded with at least one valid persona
- **Phase 3 close**: per-persona observed-vs-declared harness passing on nightly for 14 consecutive runs

## Reporting + observability

- **Per-run JSON reports** in `reports/` per QA workflow, schema documented in `carbonyl-agent-qa/docs/reporting.md`
- **Aggregated dashboard** (Phase 3 deliverable): time-series of per-layer pass rates; alert on drop below threshold
- **Drift audit report** quarterly (`.aiwg/reports/drift-audit-YYYYqQ.md`): Chromium JA4 vs stable Chrome
- **wreq sync report** quarterly: upstream commits merged, local patches maintained, security backports applied

## Explicit out-of-scope for CI

- **Hosting Carbonyl binaries for external consumers** — handled by existing release workflow in `docs/ci-cd-plan.md`
- **Production deployment of carbonyl-fleet** — deployment story is Phase 4 ops concern, separate doc
- **Cross-cloud runner fleet** — single `titan` + generic runners is sufficient until proven otherwise
- **Automated persona generation from live traffic** — corpus refresh pulls from public probe sites only; no scraping of victim sessions

## Issue filing

Initiative CI issues filed per-repo under their standard workflow-issue pattern. Umbrella tracking issue in `carbonyl-agent` (since most new CI lives there):

- `roctinam/carbonyl-agent#NEW` — CI/CD track for Trusted Automation Initiative (this doc)
- Per-workflow child issues filed with `docs/ci-cd-plan.md` approval pattern

## Open questions

- **Runner label segmentation**: add `light` and `heavy` labels, or keep all-on-titan? Revisit if QA nightly queueing becomes a problem.
- ~~**GitHub Actions for `jmagly/wreq` fork vs. Gitea mirror**~~ **Resolved 2026-04-18**: Gitea is primary (`roctinam/wreq`); all fork CI lives on Gitea. GitHub `jmagly/wreq` is publish-mirror only, no CI there.
- **Corpus privacy**: if we ever sample personas from consented telemetry instead of BrowserForge, the corpus becomes sensitive. Plan: keep corpus in a private sub-repo or encrypted branch; defer until we actually need it.
