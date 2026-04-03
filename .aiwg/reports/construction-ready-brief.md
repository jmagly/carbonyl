# Construction Ready Brief — Carbonyl Automation Layer

**Project**: Carbonyl Automation Layer
**Date**: 2026-04-03
**Status**: CONSTRUCTION READY

---

## Executive Summary

The Carbonyl Automation Layer is a Python library (~1,720 LoC) that wraps the Carbonyl terminal browser (headless Chromium) to enable programmatic web interaction for LLM agents. The library provides a persistent daemon architecture over a Unix socket, a pyte-based virtual terminal screen inspector, and a Chromium session manager with fork/snapshot/restore semantics.

The implementation is functional and has been empirically validated: the Akamai bot detection bypass (Firefox UA + `--disable-http2`) is confirmed working on poboxes.usps.com, the daemon survives client disconnects, and the screen inspection and click targeting coordinates are 1-indexed and consistent across both direct and daemon modes.

This SDLC intake was performed brownfield — the code existed before the artifacts. The elaboration phase identified three Critical/High security gaps (plaintext credentials, world-writable MFA path, unauthenticated daemon socket) that must be addressed before deployment beyond single-user development workstations. These form the core of Iteration 1.

---

## Artifact Index

| Artifact | Path | Status |
|----------|------|--------|
| Intake Form | `.aiwg/intake/intake-form.md` | Baselined |
| Project Intake (detailed) | `.aiwg/intake/project-intake.md` | Baselined |
| Solution Profile | `.aiwg/intake/solution-profile.md` | Baselined |
| Option Matrix | `.aiwg/intake/option-matrix.md` | Baselined |
| Risk Screening | `.aiwg/intake/risk-screening.md` | Baselined |
| LOM Gate Report | `.aiwg/reports/lom-gate-report.md` | PASS |
| Use Cases (5) | `.aiwg/requirements/use-cases.md` | Baselined |
| User Stories (15) | `.aiwg/requirements/user-stories.md` | Baselined |
| NFR Register (14) | `.aiwg/requirements/nfr-register.md` | Baselined |
| SAD | `.aiwg/architecture/software-architecture-doc.md` | BASELINED v1.1 |
| ADR-001: Daemon Architecture | `.aiwg/architecture/adr-001.md` | Accepted |
| ADR-002: pyte Virtual Terminal | `.aiwg/architecture/adr-002.md` | Accepted |
| ADR-003: Bot Detection Bypass | `.aiwg/architecture/adr-003.md` | Accepted |
| ADR-004: Session Persistence | `.aiwg/architecture/adr-004.md` | Accepted |
| Test Strategy | `.aiwg/testing/test-strategy.md` | Baselined |
| ABM Gate Report | `.aiwg/reports/abm-gate-report.md` | PASS |
| Iteration 1 Plan | `.aiwg/planning/iteration-001-plan.md` | Ready |
| Team Profile | `.aiwg/team/team-profile.md` | Ready |
| CI/CD Scaffold | `.aiwg/deployment/ci-cd-scaffold.md` | Ready |

---

## Key Decisions (ADR Summary)

**ADR-001 — Daemon architecture over per-request subprocess**
Browser sessions must survive client script restarts for multi-turn agent workflows. A persistent Unix socket daemon was chosen. Trade-off: three-way dispatch symmetry invariant (CarbonylBrowser / DaemonClient / `_BrowserHandler`) must be maintained manually.

**ADR-002 — pyte virtual terminal for screen parsing**
Carbonyl renders to a terminal, not pixels. A software VT100 emulator (pyte) was chosen over accessibility APIs or OCR. Trade-off: Unicode block characters used in Carbonyl's rendering can obscure adjacent text content.

**ADR-003 — Firefox UA spoofing + HTTP/2 disabling**
The Akamai bot detection chain targets three signals: JA3 TLS fingerprint, HTTP/2 SETTINGS frame, and User-Agent string. Firefox UA + `--disable-http2` eliminates two of three. JA3 remains Chromium-native (R-002, accepted risk).

**ADR-004 — Chromium user-data-dir for session persistence**
Native Chromium profile directories provide full-fidelity session persistence (cookies, localStorage, cached tokens) with zero serialization code. Trade-off: profile directories are effectively plaintext on disk; access control is directory-permission-only.

---

## Risks to Watch

| ID | Severity | Description | Mitigation |
|----|----------|-------------|------------|
| R-001 | Critical | Plaintext credentials at `~/.config/usps/credentials` | S-001: migrate to OS keyring (Iteration 1 P1) |
| R-003 | Critical | MFA code via world-writable `/tmp/usps_mfa_code` | S-002: atomic write to `~/.config/usps/mfa_code` mode 600 (Iteration 1 P1) |
| R-005 | High | Unauthenticated daemon socket (local attack chain with R-001) | S-003: `os.chmod(socket_path, 0o600)` at bind (Iteration 1 P1) |
| R-011 | High | Chromium sandbox disabled (`--no-sandbox`) | Container-only deployment; never on multi-user hosts |
| R-002 | Medium | JA3 TLS fingerprint remains Chromium-native | Accepted; monitor for Akamai escalation |

---

## Iteration 1 Sprint Goal

**Close the local privilege escalation chain (R-001 / R-003 / R-005) and establish the browser stub seam that unblocks the integration test tier.**

8 stories, 17 story points, 2-week sprint (2026-04-07 → 2026-04-18).

Priority breakdown:
- P1 (security hardening): S-001 credential encryption, S-002 MFA path hardening, S-003 socket permissions, S-004 profile directory permissions
- P2 (test infrastructure): S-005 browser stub + PTY injection seam, S-006 unit test suite
- P3 (maintainability): S-007 `pyproject.toml` with `python_requires`, S-008 dispatch symmetry checklist

---

## First Steps for Construction

1. **Review SAD §8.3** — understand the security control targets before touching the security stories
2. **Set up Gitea Actions runner** — the CI scaffold at `.aiwg/deployment/ci-cd-scaffold.md` requires a runner with Python 3.11; no Chromium needed for the lint/unit/integration pipeline
3. **Start with S-002** (MFA path) — lowest risk, highest impact for R-003; establishes the pattern for the other file-permission stories
4. **Build browser stub (S-005) before writing integration tests** — it's a prerequisite for the entire integration test tier; all other test stories depend on it
5. **Run E2E manually before marking Sprint done** — bot detection bypass (UC-005) cannot be automated; manual verification against poboxes.usps.com is required before the Transition gate
