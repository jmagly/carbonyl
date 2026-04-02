# Option Matrix (Project Context & Intent)

**Purpose**: Capture what this project IS — its nature, audience, constraints, and intent — to determine appropriate SDLC framework application.

**Generated**: 2026-04-01 (from codebase analysis)

---

## Step 1: Project Reality

### What IS This Project?

**Project Description**:

> Carbonyl is a Chromium-based terminal browser — a thin Rust integration layer (~4,800 LoC) that routes Chromium's rendering pipeline to ANSI/xterm escape sequences. It is a workspace fork of the upstream project `fathyb/carbonyl` (v0.0.3, BSD-3-Clause), maintained under `roctinam` on an internal Gitea forge. The upstream is public, open source, and in a low-activity phase post-v0.0.3. This fork serves as a workspace for potential local modifications, with GitHub as a publish target.

---

### Audience & Scale

**Who uses this?**

- [x] Just me / small team (workspace fork, personal/organizational use)
- [x] External users (upstream consumers of the open-source binary via Docker/NPM) — but this fork is not yet published to them

**Audience Characteristics**:
- Technical sophistication: Technical (developers using terminal environments)
- User risk tolerance: Experimental OK (pre-1.0 software, users expect rough edges)
- Support expectations: Community/best-effort (open source)

**Usage Scale**:
- Active users of this fork: 1 (roctinam, workspace)
- Active users of upstream: Unknown but meaningful (npm downloads, Docker pulls)
- Request volume: N/A (CLI tool, not a service)
- Data volume: N/A (stateless per invocation)
- Geographic distribution: Global (public open source binary)

---

### Deployment & Infrastructure

**Deployment Model**:
- [x] Client-only — desktop/terminal CLI tool (single binary + shared library)
- [x] Container — Docker image distributed via Docker Hub

**Where does this run?**
- [x] Desktop / Terminal (Linux, macOS, WSL) — primary
- [x] Container (Docker) — alternative distribution
- [x] Cloud (CI builds, GitHub Releases) — artifacts only

**Infrastructure Complexity**:
- Deployment type: Client binary + Docker image; no server
- Data persistence: None (stateless); user data delegated to Chromium's profile dir
- External dependencies: 0 runtime API dependencies (self-contained binary)
- Network topology: Standalone (the browser itself makes network calls, but no backend service)

---

### Technical Complexity

**Codebase Characteristics**:
- Size: ~4,800 LoC tracked (small); Chromium submodule is 30M+ LoC (external dependency, not maintained here)
- Languages: Rust (primary, 67%), C++ (13% — Chromium bridge), Shell (20% — build scripts)
- Architecture: Thin integration layer — Rust shared library loaded by patched Chromium headless shell
- Team familiarity: Brownfield (inherited from upstream, not greenfield)

**Technical Risk Factors**:
- [x] Performance-sensitive — 60 FPS rendering, < 1s startup, 0% idle CPU; tight perf budget
- [x] Integration-heavy (Chromium FFI, GN build system, Mojo IPC, multiplatform toolchain)
- [ ] Security-sensitive — no PII, no auth, stateless client tool
- [ ] Data integrity-critical — no persistent data
- [ ] High concurrency — single-user CLI, no multi-tenancy
- [ ] Complex business logic — rendering math is complex but bounded

---

## Step 2: Constraints & Context

### Resources

**Team**:
- Size: 1 (roctinam as workspace owner; roctibot as automation collaborator)
- Experience: Senior (30+ years system engineering per user context)
- Availability: Part-time / as-needed (workspace fork, not primary project)

**Budget**:
- Development: Zero (open source, personal time)
- Infrastructure: Minimal (self-hosted Gitea, standard CI runners)
- Timeline: No deadline (exploratory fork)

---

### Regulatory & Compliance

**Data Sensitivity**:
- [x] Public data only — no privacy concerns
- No PII, no PHI, no payment data

**Regulatory Requirements**:
- [x] None for the fork itself
- [~] H.264 codec: Proprietary. Included in Chromium build args (`enable_h264 = true`). MPEG-LA licensing applies if redistributing commercially. Not a concern for personal/non-commercial fork.
- No GDPR, HIPAA, PCI-DSS, SOX, FedRAMP, SOC2 requirements

**Contractual Obligations**:
- BSD-3-Clause: Attribution required, no additional obligations
- No SLAs, no customer contracts, no audit rights

---

### Technical Context

**Current State**:
- Stage: Early public release (v0.0.3), brownfield fork
- Test coverage: 0% (none)
- Documentation: Good README + changelog; no architecture docs, no API docs
- Deployment automation: Scripts-based (`scripts/*.sh`); no CI pipeline in fork

**Technical Debt**:
- Severity: Minor
- Type: Tests (none), CI (none), Unicode gap in nav bar, H.264 licensing
- Priority: Can wait — no blockers for current workspace use

---

## Step 3: Priorities & Trade-offs

### What Matters Most?

**Priority Ranking** (1 = most important):
1. **Delivery speed** — Stay close to upstream, apply changes quickly
2. **Cost efficiency** — Minimize overhead; lean process for a solo workspace fork
3. **Quality/security** — Maintain upstream code quality; no security regressions
4. **Reliability/scale** — N/A for CLI tool; not a scaling concern

**Priority Weights**:

| Criterion | Weight | Rationale |
|-----------|--------|-----------|
| Delivery speed | 0.40 | Solo workspace fork; want to move fast, track upstream |
| Cost efficiency | 0.35 | No budget, personal time; overhead must be minimal |
| Quality/security | 0.20 | Maintain upstream quality bar; no security-critical additions planned |
| Reliability/scale | 0.05 | CLI tool; no SLA, no uptime concern |
| **TOTAL** | **1.00** | |

**What are we optimizing for?**
> Staying lightweight — easy to track upstream changes, easy to apply local patches, easy to publish forks to GitHub when needed. Process overhead must be near zero.

**What are we willing to sacrifice?**
> Comprehensive test coverage (0% → some is fine), formal architecture docs, runbooks, PR review process. This is a solo workspace.

**What is non-negotiable?**
> BSD-3-Clause attribution. Conventional commits (already in place). Not introducing security regressions into the binary. Not diverging from upstream in ways that make re-syncing painful.

---

## Step 4: Intent & Decision Context

### Why This Intake Now?

**Trigger**:
- [x] Documenting existing project — workspace fork just created; never had formal intake
- [x] Team expansion preparation — roctibot added as collaborator; potential for automation workflows
- [x] Establishing baseline — want to know what we have before modifying it

**What decisions need making?**
> 1. Should we add a CI pipeline to the fork? (Answer: Yes — lightweight cargo build + test)
> 2. How to track upstream divergence? (Answer: Conventional commits + optional `FORK.md`)
> 3. What's the publish path when changes are ready? (Answer: push to `github` remote explicitly)

**What's uncertain?**
> - Whether any substantive local changes to the codebase are planned (vs. just maintaining the fork)
> - Whether upstream will resume activity or this fork will become the primary evolution
> - Whether H.264 will need to be addressed if distribution scope expands

**Success criteria for this intake**:
> Clear snapshot of what Carbonyl is, what risks exist, and what minimal process to apply to the workspace fork. Shared reference for future development decisions.

---

## Step 5: Framework Application

### Relevant SDLC Components

**Templates** (applicable):
- [x] Intake (project-intake, solution-profile, option-matrix) — this document set
- [ ] Requirements — Skip; clear scope, solo developer, upstream defines requirements
- [ ] Architecture docs (SAD, ADRs) — Skip for now; add ADR only if a significant divergence decision is made
- [ ] Test strategy — Skip formal template; add inline test comments when writing tests
- [ ] Security/threat model — Skip; no PII, no auth, stateless tool
- [ ] Deployment plan/runbook — Skip; scripts-based, no service to operate

**Commands** (applicable):
- [x] `intake-from-codebase` — used to generate this document set
- [ ] Flow commands — Skip until active development begins
- [ ] Quality gates — Skip; no team coordination needed

**Agents** (applicable):
- [x] `code-reviewer` — Use when making code changes to Rust modules
- [x] `security-auditor` — Use before any publish if `unsafe` code is modified
- [ ] Core SDLC agents — Skip; solo, lightweight
- [ ] Operations specialists — N/A
- [ ] Enterprise specialists — N/A

**Process Rigor Level**:
- [x] Minimal — README, lightweight notes, conventional commits, ad-hoc workflow
- [ ] Moderate — Deferred until active development justifies it
- [ ] Full / Enterprise — Not applicable

### Rationale for Framework Choices

> Carbonyl fork is a solo workspace on a CLI tool with no users, no SLA, no compliance. Maximum useful process is: conventional commits (already in place), a basic CI pipeline, and this intake document set. Everything else is overhead that would slow down the primary goal — staying close to upstream and being able to publish patches quickly.

**What we're skipping and why**:
> - Requirements templates: upstream defines requirements; no new features planned yet
> - Architecture docs: upstream README + code are sufficient; document only if we diverge significantly
> - Security templates: no PII, no auth, no attack surface beyond what Chromium already manages
> - Formal test strategy: add tests pragmatically when modifying modules; no coverage target imposed
> - Deployment runbook: scripts already exist; CLI tool needs no operational runbook
>
> Will revisit if: local development scope expands significantly, team grows, or if planning commercial redistribution.

---

## Step 6: Evolution & Adaptation

### Expected Changes

- [x] Technical pivot possible — may apply patches before upstreaming; nature unclear
- [ ] User base growth — not applicable (workspace fork, not a service)
- [ ] Team expansion — unlikely beyond roctibot automation
- [ ] Compliance requirements — none anticipated

**Adaptation Triggers**:
> - Add architecture docs if we make a significant architectural change (e.g., replacing H.264, adding a service wrapper)
> - Add requirements templates if scope expands to a new feature that needs spec
> - Add security review if modifying `unsafe` FFI code or adding network-facing functionality
> - Escalate to Moderate rigor if a second developer joins actively

**Planned Framework Evolution**:
- Now: Intake documents + optional CI addition
- 3 months: Re-evaluate based on whether active development has occurred
- 6 months: If upstream inactive and we're maintaining: adopt Moderate rigor (ADRs, test plan)
- 12 months: Reassess if scope or team has changed
