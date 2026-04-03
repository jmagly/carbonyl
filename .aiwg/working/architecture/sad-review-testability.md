---
title: Testability Review — Carbonyl Automation Layer SAD
reviewer: Test Architect
date: 2026-04-03
document-reviewed: software-architecture-doc.md v1.0
verdict: CONDITIONAL
---

# Testability Review — Carbonyl Automation Layer SAD

**Reviewer**: Test Architect
**Date**: 2026-04-03
**Document Reviewed**: software-architecture-doc.md v1.0
**Verdict**: CONDITIONAL

---

## Summary

The SAD describes a four-module automation layer with a reasonably narrow interface surface. `ScreenInspector` and `SessionManager` are cleanly isolatable for unit testing, and the newline-delimited JSON wire protocol makes the daemon boundary mockable without a live browser. However, the dual-mode dispatch pattern in `CarbonylBrowser` (direct vs. daemon), the absence of any stated CI test strategy, and the structural coupling to a live PTY process create material gaps in integration coverage — particularly around daemon reconnect, process-death recovery, and bot-bypass verification. Several NFRs that are marked "Met" have no automated validation in CI to enforce that status over time.

---

## Testability Analysis

### Unit Testability

`ScreenInspector` is the most testable component in the system. It operates on a snapshot of `raw_lines()` and has no external dependencies. All methods (`render_grid`, `find`, `annotate`, `crosshair`, `dot_map`, `summarise_region`) can be exercised by constructing a synthetic list of strings. A full unit suite is feasible with zero process or filesystem setup.

`SessionManager` is largely testable with a temporary filesystem. Operations (`create`, `fork`, `snapshot`, `restore`, `clean_stale_lock`, `is_live`) depend only on `pathlib` and `shutil`. Using `tmp_path` (pytest) or `tempfile.TemporaryDirectory`, all state transitions and validation paths — including the slug regex, `FileExistsError`, `RuntimeError` on live-lock, and stale PID detection via `os.kill(pid, 0)` — can be covered without a real Chromium process.

`CarbonylBrowser` is the least isolatable. Every method that is not guarded by `if self._daemon_client:` requires a live PTY and a running Carbonyl process. The `drain()` loop, coordinate extraction (`raw_lines`, `find_text`), and input dispatch (`send`, `click`, `mouse_path`) are all tightly coupled to `pexpect.spawn`. There is no seam to inject a fake PTY or a pre-populated pyte screen, making unit coverage of these paths dependent on integration infrastructure.

`DaemonClient` is mechanically testable: each method is a thin `_rpc()` wrapper, and `_rpc()` itself operates over a socket. A test can stand up `_BrowserServer` against a fake `CarbonylBrowser` stub (or use a real daemon with a pre-set screen state) and exercise every RPC path. However, no such stub is described in the SAD, and the three-way symmetry requirement (NFR-013) is acknowledged as lacking automated enforcement.

### Integration Testability

The daemon/socket architecture is a genuine testability asset. The newline-delimited JSON protocol is human-readable, debuggable with `socat`, and fully exercisable without a real browser by standing up `_BrowserServer` against a minimal `CarbonylBrowser` shim that returns scripted screen buffers. This means integration tests for daemon reconnect, mid-session client disconnect (NFR-004), and RPC error propagation (NFR-006) do not require Chromium.

What the architecture does not provide: there is no test double, interface abstraction, or injection point for the Carbonyl binary itself. The binary resolution path (`_local_binary()`, Docker fallback) and the PTY spawn are implemented as direct calls with no substitution mechanism. Full end-to-end integration tests are therefore blocked on binary availability in CI. For any CI environment without the pre-built binary, the Docker fallback path is untested, and there is no way to run even a smoke test of `CarbonylBrowser.open()` without resolving this dependency.

The mode-switching logic in `CarbonylBrowser` (`if self._daemon_client:`) is an implicit branch that must be covered by running the same scenario in both modes. The SAD acknowledges this as a dual code path (AD-06) but does not describe how test coverage will enforce parity. NFR-013 ("Partially Met") makes this risk concrete: silent API gaps have already occurred in the existing codebase.

### NFR Verifiability

| NFR | Verifiable Without Live Browser | Current Evidence |
|-----|----------------------------------|------------------|
| NFR-001: drain() time bound | No — requires PTY timing | Asserted in code; no CI benchmark |
| NFR-002: find_text() under 100 ms | Yes — synthetic pyte screen | Asserted in code; no benchmark test |
| NFR-003: RPC round-trip under 20 ms | Yes — local socket microbenchmark | No benchmark captured in CI |
| NFR-004: Daemon survives disconnect | Yes — socket-level integration test | Described as "Met"; no automated test |
| NFR-005: SIGKILL profile hygiene | Partially — PID/lock logic is unit-testable; full Chromium crash is not | Manual exercise only |
| NFR-006: Process death recovery | Partially — EOF handling is unit-testable; send-on-dead-child requires PTY | "Partially Met"; no structured error type |
| NFR-007: Socket permissions | Yes — stat the socket file after daemon start | Not enforced by code; no test |
| NFR-008: Profile directory permissions | Yes — stat after `SessionManager.create()` | Not enforced by code; no test |
| NFR-014: No stdout contamination | Yes — subprocess capture | No test |

NFR-001 through NFR-003 are stated as "Met" based on code inspection, but no benchmark suite captures these figures in CI. Regressions in drain timing, find_text latency, or RPC overhead will be invisible until they surface in production automation scripts. NFR-007 and NFR-008 are "Not Met" by the SAD's own admission; they need both a code fix and a corresponding test to move to "Met."

---

## Gaps and Risks

**Gap 1 — No test seam for the PTY layer.** `CarbonylBrowser` in direct mode cannot be instantiated without a live Carbonyl process. There is no interface or injection point that would allow a pre-populated `pyte.Screen` to be substituted. This makes unit coverage of coordinate extraction, drain behavior, and input dispatch entirely dependent on integration infrastructure.

**Gap 2 — Daemon reconnect path is untested.** UC-004 Extension E1 (daemon crashed between runs) and NFR-006 (graceful recovery) are the highest-reliability risks in the system. The architecture supports testing this path via socket-level manipulation without a real browser, but no test is described or implied anywhere in the SAD or NFR register.

**Gap 3 — Three-way dispatch symmetry has no enforcement mechanism.** The pattern that caused a silent API gap before (NFR-013) has no test gate. Any new method added to `CarbonylBrowser` that omits its `DaemonClient` counterpart will break daemon-mode callers at runtime, not at PR merge time.

**Gap 4 — Performance NFRs have no CI artifacts.** NFR-001, NFR-002, and NFR-003 are asserted as "Met" by reading the code, not by running benchmarks. Without captured baselines, there is no regression signal. Given that `drain()` timing correctness is the sole mechanism for page-render synchronization, an undetected regression here breaks every use case.

**Gap 5 — Bot-bypass behavior is structurally unverifiable.** UC-005 (bypass Akamai) and NFR-SEC-003 (mouse path entropy) cannot be verified by a unit or integration test against a controllable server. The SAD correctly identifies the JA3 gap, but there is no described strategy — not even a contract test against a local bot-detection simulator — for validating that the four bypass layers work as a system.

**Gap 6 — Security NFRs NFR-007 and NFR-008 are "Not Met" with no test blocking the gap.** File permission enforcement is missing from the code, and no test exists to catch a regression if permissions are inadvertently changed. These are straightforward to verify with a post-creation `os.stat()` assertion.

---

## Recommendations

1. **Add a `ScreenBuffer` abstraction or constructor to `CarbonylBrowser`** that accepts a pre-populated `pyte.Screen` object, enabling unit tests for `find_text`, `raw_lines`, `extract_text`, and coordinate logic without a live PTY. This is a small refactor with significant coverage payoff.

2. **Write a daemon integration test fixture** that spins up `_BrowserServer` against a minimal `CarbonylBrowser` stub returning scripted screen content. Use this fixture to cover: daemon reconnect after client disconnect, RPC error propagation, socket cleanup on daemon death, and the three-way dispatch symmetry for all existing commands (resolving NFR-013).

3. **Add permission assertion tests for NFR-007 and NFR-008.** After `SessionManager.create()` and after `_BrowserServer` socket creation, assert `os.stat().st_mode & 0o777` equals the required mode. These tests will fail until the production code is fixed with explicit `os.chmod` calls, making them blocking gates, not just coverage additions.

4. **Capture performance baselines in CI for NFR-001 through NFR-003.** Add pytest-benchmark or equivalent timing assertions with tolerances derived from the NFR acceptance criteria. Mark these tests as non-blocking on slow CI runners but store the results as artifacts to detect drift.

5. **Introduce a `CarbonylBrowserDead` exception** (or equivalent structured error) for process-death conditions. This makes NFR-006's "Partially Met" state fully testable: a test can inject `pexpect.EOF`, assert the specific exception type is raised, and verify the daemon socket is cleaned up. Raw `pexpect.EOF` propagation is untestable at the caller level without coupling to pexpect internals.

6. **Define a CI test matrix covering both direct mode and daemon mode** for every public method in `CarbonylBrowser`. Until this parity exists, daemon-mode regressions will only be discovered by automation scripts in production. The matrix can be parameterized in pytest via a fixture that returns either a direct-mode or daemon-mode browser instance backed by the stub from Recommendation 2.
