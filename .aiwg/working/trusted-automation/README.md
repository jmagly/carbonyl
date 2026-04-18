# Trusted Automation Initiative — Document Corpus

**Goal:** Make Carbonyl a credible headless browser for personal automation agents against modern bot-detection stacks (Akamai Bot Manager, DataDome, PerimeterX/HUMAN, Cloudflare).

**Scope:** Multi-repo initiative spanning `carbonyl` (core), `carbonyl-agent` (SDK + behavioral), `carbonyl-agent-qa` (test harness), and `carbonyl-fleet` (deferred orchestration).

**Status:** Concept / Inception artifacts. Construction is gated on phase 1 validation (see `05-phase-plan.md`).

## Document index

| # | Doc | Purpose |
|---|-----|---------|
| 00 | [Vision](00-vision.md) | Why this initiative exists, success criteria, non-goals |
| 01 | [Requirements](01-requirements.md) | Functional + non-functional requirements, traceable to acceptance tests |
| 02 | [Architecture](02-architecture.md) | SAD — C4 context/container/component, DFD, repo split |
| 03 | [Threat Model](03-threat-model.md) | Attacker (bot detector) perspective across detection layers 1–6 |
| 04 | [Test Strategy](04-test-strategy.md) | Per-layer acceptance tests, integration harness design |
| 05 | [Phase Gate Plan](05-phase-plan.md) | Flow-gate track with validation milestones |
| 06 | [Research Index](06-research-index.md) | Consolidated research findings, citations, open questions |
| 07 | [Fingerprint Registry Design](07-fingerprint-registry-design.md) | Owned persona registry: schema, sampler, validator, library choice |
| 08 | [Roadmap](08-roadmap.md) | Consolidated executive view: phase dependencies, repo matrix, critical path, governance |
| 09 | [CI Plan](09-ci-plan.md) | Per-repo workflows, cross-repo coordination, `jmagly/wreq` fork lifecycle, corpus refresh pipeline |

## Issue map

Filed under umbrella epic `roctinam/carbonyl#<TBD>`. Each workstream has its own ticket in its owning repo.

See `05-phase-plan.md` for the dependency graph.

## Origin

Derived from `roctinam/carbonyl#57` (uinput for trusted input) after discovery that `isTrusted: false` is only one of ~6 detection layers. This corpus generalises #57 into a full trust/automation program.

## Upstream dependencies

- **`roctinam/wreq`** (Gitea primary) — TLS/HTTP2 fingerprint library fork (of `0x676e67/wreq`). Phase 3 egress library. `jmagly/wreq` on GitHub is the one-way publish mirror. Fork lifecycle in `09-ci-plan.md`.
- **`roctinam/carbonyl-fingerprint-corpus`** (Gitea, private) — joint-distribution persona tuples + reference fingerprints per Chrome version. Consumed by `carbonyl-fingerprint` crate at build.
- **BrowserForge** — upstream corpus source (MIT). Phase 3A.2 dependency; our corpus bootstraps from and extends it.
- **Chromium M147** (current) — Carbonyl's upstream. Fingerprint corpus tracks stable Chrome; see `docs/chromium-upgrade-plan.md` for the rebase cadence.
