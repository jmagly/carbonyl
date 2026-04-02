# Solution Profile (Current System)

**Document Type**: Existing System Profile
**Generated**: 2026-04-01

---

## Current Profile

**Profile**: Prototype / Early Open Source Tool

**Selection Rationale**:
- CLI tool, single-user per invocation — no server, no multi-tenancy
- No user auth, no PII, no compliance requirements
- No automated tests
- Upstream actively maintained through v0.0.3; now in low-activity phase
- Small codebase (~4,800 LoC tracked) with well-separated concerns
- Distribution via Docker, NPM, and binary releases — public-facing but tooling, not SaaS

**Effective Stage**: Early public release, brownfield fork (workspace copy of upstream)

---

## Current State Characteristics

### Security

**Posture**: Minimal (intentional — appropriate for tool)

| Control | Status | Notes |
|---------|--------|-------|
| Authentication | N/A | CLI tool, no auth model |
| Authorization | N/A | Single user, no roles |
| Secrets in code | None detected | Clean |
| Chromium sandbox | Disabled in Docker | `--no-sandbox` — intentional for headless; document clearly |
| FFI `unsafe` code | Present | `bridge.rs`, `tty.rs`, `window.rs` — contained, no obvious exploits |
| H.264 licensing | Potential gap | Commercial redistribution may require MPEG-LA license |

**Security Recommendation**: No changes needed for tooling use. If packaging for commercial redistribution, audit H.264 licensing. Document `--no-sandbox` rationale explicitly.

---

### Reliability

**Current SLOs**: None defined (CLI tool, no uptime contract)

| Metric | Status | Notes |
|--------|--------|-------|
| Availability | N/A | Single-user CLI |
| Startup latency | < 1 second | Stated in README, validated by design |
| Frame rate | 60 FPS target | Configurable via `--fps` |
| CPU idle | 0% | Event-driven architecture |
| Error handling | Basic | `log.rs` + `CARBONYL_ENV_DEBUG`, no structured error reporting |

**Monitoring Maturity**: None — appropriate for CLI, not needed.

**Reliability Recommendation**: For local/personal use, no changes needed. If building a service wrapper around Carbonyl, add structured logging and health checks.

---

### Testing & Quality

**Test Coverage**: 0% — no test suite found

| Test Type | Status |
|-----------|--------|
| Unit tests | Not found |
| Integration tests | Not found |
| End-to-end tests | Not found |
| CI automated testing | Not found |

**Code Quality Indicators**:
- Well-structured module separation (`input/`, `output/`, `browser/`, `gfx/`, `ui/`, `cli/`, `utils/`)
- Conventional commits and semantic versioning enforced
- Changelog maintained via `git-cliff`
- `unsafe` code isolated to FFI boundaries and TTY syscalls
- One open TODO: Unicode in `navigation.rs`

**Quality Recommendation**: Add smoke tests for the Rust library (unit tests for quantizer, parser, painter) before making significant modifications. No pressure to reach high coverage on initial pass.

---

### Process Rigor

**SDLC Adoption**: Partial — conventional commits, changelog, semantic versioning; no formal requirements or test strategy.

| Practice | Status |
|----------|--------|
| Version control | Git, semantic versioning |
| Conventional commits | Enforced (cliff.toml) |
| Code review | Unknown (upstream had 11 contributors; no PR config visible in fork) |
| CI/CD | Build scripts only; no GitHub Actions found |
| Architecture docs | None |
| API docs | None |
| Runbooks | None (N/A for CLI) |

**Process Recommendation**: For the workspace fork, adopt lightweight SDLC:
1. Add `.github/workflows/` for CI (cargo build + test)
2. Document any divergence from upstream in a `FORK.md` or ADR
3. Use conventional commits (already in place)

---

## Recommended Profile Adjustments

**Current Effective Profile**: Prototype fork of an early-stage open source tool

**Recommended Profile**: Lightweight Open Source — Moderate rigor

**Rationale**:
- The upstream project is well-structured with good code quality
- No compliance, no users, no SLA — overhead of heavyweight SDLC is wasteful
- The primary risk is diverging from upstream without tracking intent
- Adding CI (build + basic tests) provides high value for low cost

**Tailoring Notes**:
- Keep process lean (solo or small team)
- Skip: threat models, compliance evidence, formal requirements, runbooks
- Add: CI pipeline, basic unit tests for Rust modules, fork-divergence log

---

## Improvement Roadmap

### Phase 1 — Immediate (< 2 weeks)
- [ ] Add `.github/workflows/ci.yml` — `cargo build` + `cargo test` on push
- [ ] Add `FORK.md` or ADR documenting purpose of the fork and divergence plan
- [ ] Document `--no-sandbox` rationale in README or Dockerfile comment
- [ ] Resolve TODO: Unicode in `src/ui/navigation.rs`

### Phase 2 — Short-term (1–3 months)
- [ ] Add Rust unit tests for: `quantizer.rs`, `parser.rs`, `painter.rs`
- [ ] Pin Chromium submodule commit explicitly in documentation
- [ ] Audit H.264 licensing if planning commercial redistribution
- [ ] Set up `renovate` or `dependabot` for Rust crate updates

### Phase 3 — If Scope Expands
- [ ] If building a service wrapper: add health check endpoint, structured logging
- [ ] If team grows: add PR review requirements, branch protection on `origin`
- [ ] If commercial: full H.264 licensing resolution, consider replacing with AV1/VP9
- [ ] If upstreaming changes: track commits in a `UPSTREAM-SYNC.md` with delta notes
