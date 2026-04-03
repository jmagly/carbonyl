---
title: Test Strategy — Carbonyl Automation Layer
version: "1.0"
date: 2026-04-03
scope: automation/ module
status: APPROVED
phase: Elaboration
---

# Test Strategy — Carbonyl Automation Layer

**Version**: 1.0
**Date**: 2026-04-03
**Scope**: `automation/` module (CarbonylBrowser, DaemonClient / _BrowserServer, SessionManager, ScreenInspector)

---

## 1. Testing Objectives

1. Verify that all four components behave correctly against their documented contracts — NFR acceptance criteria are treated as test specifications, not prose.
2. Enforce the three-way dispatch symmetry (CarbonylBrowser / DaemonClient / _BrowserServer._dispatch) as a blocking CI gate, not a code-review convention.
3. Close the two "Not Met" security NFRs (NFR-007 socket permissions, NFR-008 profile permissions) by making their test assertions fail before the production fix is merged — so the gate drives the implementation.
4. Establish performance baselines for NFR-001 through NFR-003 in CI before construction begins, so regressions are detected automatically rather than by production script failures.
5. Contain reliance on live Carbonyl binary to a clearly bounded E2E tier so that the majority of the test suite runs without a binary in the standard CI runner.

---

## 2. Scope and Boundaries

### In Scope

- All public methods on `CarbonylBrowser`, `DaemonClient`, `SessionManager`, and `ScreenInspector`
- Both operating modes of `CarbonylBrowser` (direct PTY and daemon-proxied) for every public method
- Daemon lifecycle: start, client connect, client disconnect, daemon crash, socket cleanup
- Session lifecycle: create, fork, snapshot, restore, stale-lock cleanup, permission enforcement
- RPC error propagation: malformed JSON, unknown command, handler exception
- Performance contracts: drain time bound (NFR-001), find_text latency (NFR-002), RPC round-trip (NFR-003)
- Security invariants: socket file mode (NFR-007), profile and session.json file modes (NFR-008)
- Coordinate convention: 1-indexed return values for all find/locate operations (NFR-012)
- Process-death recovery: EOF handling in drain(), send() on dead child, DaemonClient on crashed daemon (NFR-006)

### Out of Scope (with rationale)

| Area | Rationale |
|------|-----------|
| UC-005 bot-detection bypass (Akamai `_abck` validation) | Adversarial, classifier-dependent property. No controllable server exists that replicates Akamai's sensor scoring. Accepted limitation per SAD Section 10.5. Manual site verification is the validation path. |
| JA3 / TLS fingerprint fidelity | Requires TLS-intercepting proxy infrastructure outside this layer's boundary. Noted as known gap in SAD Section 11. |
| Mouse path entropy scoring (NFR-SEC-003) | Entropy quality is evaluated by the remote classifier, not a local assertion. Structural test (non-null, non-identical across calls) is in scope; behavioral adequacy is not. |
| macOS compatibility | Untested per SAD Section 10.4. Not a stated requirement for construction. |
| Docker fallback path | Requires Docker daemon in CI. Treated as out of scope for automated tests; flagged as an acceptance test item for release. |
| MFA code delivery (NFR-009) | Applies to downstream scripts, not the library itself. Enforcement via code-review policy. |

---

## 3. Test Levels

### 3.1 Unit Tests

**Framework**: pytest  
**Blocking gate**: PR merge (CI must pass)  
**Coverage tool**: coverage.py with branch coverage enabled

**ScreenInspector** — full unit coverage is achievable with zero infrastructure. Tests pass a synthetic `list[str]` of 50 rows (220 chars each) to the inspector and assert on: `find()` coordinate return values and 1-indexing; `render_grid()` output format; `crosshair()` bounds; `annotate()` context window correctness; `summarise_region()` regex matches for checkbox, input, button, and URL patterns.

**SessionManager** — use `pytest`'s `tmp_path` fixture as the session root. Tests cover: `create()` slug validation (valid, too-short, invalid chars); `FileExistsError` on duplicate create; `fork()` copies profile and cleans SingletonLock; `snapshot()` naming convention; `restore()` refuses live-locked sessions (`RuntimeError`); `clean_stale_lock()` calls `os.kill(pid, 0)` and removes only stale locks (use `os.getpid()` for a live PID, a subprocess that has exited for a dead PID); **permission assertions** — after `create()`, `fork()`, and `restore()`, assert `os.stat().st_mode & 0o777` equals `0o700` for directories and `0o600` for `session.json`. These tests will fail until NFR-008 is fixed and serve as the blocking gate for that fix.

**CarbonylBrowser (screen logic only)** — this tier is enabled by Recommendation 1 from the testability review: a constructor or factory that accepts a pre-populated `pyte.Screen`. Once that seam exists, tests cover: `find_text()` returns correct 1-indexed col/row; `raw_lines()` returns unfiltered rows; `extract_text()` strips block-drawing characters; `page_text()` output. These tests require no PTY or binary.

**Performance (NFR-002)** — `find_text("nonexistent")` on a fully-populated 220×50 screen must complete in under 100 ms. Assert using `time.monotonic()`. Mark slow on CI runners with `pytest.ini` timeout but store result as artifact.

### 3.2 Integration Tests

**Framework**: pytest  
**Blocking gate**: PR merge (CI must pass)  
**Infrastructure**: `_BrowserServer` started against a `CarbonylBrowser` stub that returns scripted screen content without a live PTY. The stub is the prerequisite infrastructure item for this tier.

**Daemon lifecycle** — stand up a real `_BrowserServer` with the browser stub, connect a `DaemonClient`, and verify: `is_daemon_live()` returns True; all public commands round-trip correctly (three-way symmetry test — parameterize over every command in the dispatch table); client disconnect does not crash the server (NFR-004); a second `DaemonClient` can connect after the first disconnects; `close` command triggers clean shutdown.

**Daemon reconnect (UC-004 E1)** — simulate daemon crash by killing the server process; assert `is_daemon_live()` returns False and cleans the stale socket file; assert a fresh daemon can be started on the same session name.

**RPC error propagation (NFR-006)** — inject `pexpect.EOF` into the stub; assert `DaemonClient._rpc()` raises `RuntimeError("Daemon closed connection")`. Send an unknown command; assert the response is `{"ok": false, "error": "..."}` without crashing the server thread.

**Socket permission (NFR-007)** — after `_BrowserServer` bind, assert `os.stat(socket_path).st_mode & 0o777 == 0o600`. This test fails until the `os.chmod` call is added to production code and is a blocking gate for NFR-007.

**Performance (NFR-003)** — measure `DaemonClient.page_text()` round-trip over the local socket with the stub; assert mean latency under 20 ms across 100 iterations.

**Mode-parity matrix** — parameterize every public `CarbonylBrowser` method as `(direct_stub | daemon_via_stub)` and assert identical return values. This is the automated enforcement mechanism for NFR-013.

### 3.3 End-to-End Tests

**Framework**: pytest with live binary fixture  
**Blocking gate**: Release gate (Construction → Transition). Not required for PR merge.  
**Infrastructure**: Carbonyl binary present at `build/pre-built/x86_64-unknown-linux-gnu/carbonyl`; tests run against a local HTTP server (e.g., `http.server`) serving static HTML pages — no external network dependency.

Scenarios:
- **UC-001 (simplified)**: navigate to a login form on the local test server, enter text into fields located by `find_text()`, click submit, verify post-submit page text.
- **UC-002 / UC-003**: load a page with known layout, call `inspector()`, verify `find()` and `render_grid()` output matches page content.
- **UC-004 daemon persistence**: start daemon, disconnect client, reconnect, verify page state is preserved.
- **NFR-001 drain time bound**: call `drain(2)` and assert it returns within 2.5 seconds.
- **NFR-005 SIGKILL recovery**: spawn browser, send SIGKILL to Carbonyl PID, assert `clean_stale_lock()` succeeds and `open()` can start a new process on the same session.

Bot-detection (UC-005) is explicitly excluded from this tier. See Section 2.

---

## 4. Coverage Targets

| Component | Line Coverage | Branch Coverage | Blocking |
|-----------|---------------|-----------------|----------|
| ScreenInspector | 90% | 85% | Yes — PR merge |
| SessionManager | 85% | 80% | Yes — PR merge |
| CarbonylBrowser (screen logic, post-seam) | 80% | 75% | Yes — PR merge |
| CarbonylBrowser (PTY paths) | E2E tier only | E2E tier only | Yes — release |
| DaemonClient | 85% | 80% | Yes — PR merge |
| _BrowserServer._dispatch | 100% commands covered | — | Yes — PR merge |

Coverage cannot decrease sprint over sprint. The baseline is established at the start of construction iteration 1 (may be 0% for new seams). Any PR that reduces coverage below threshold is rejected by CI without exception.

---

## 5. Test Environment Requirements

| Tier | Environment | Binary Required | Network Required |
|------|-------------|-----------------|-----------------|
| Unit | Any Python 3.11+ environment | No | No |
| Integration | Any Python 3.11+ environment | No | No (Unix socket, local only) |
| E2E | Linux x86_64, Python 3.11+, Carbonyl binary present | Yes | No (local HTTP server) |
| Bot-detection validation | Live target site, manual | Yes | Yes (external) |

The `CarbonylBrowser` stub required for the integration tier must be implemented as a pytest fixture before any integration tests are written. It is a construction prerequisite, not a nice-to-have.

---

## 6. NFR Test Mapping

| NFR ID | Test Approach | Tier | Automated |
|--------|---------------|------|-----------|
| NFR-001 drain() time bound | `time.monotonic()` assertion in E2E fixture | E2E | Yes |
| NFR-002 find_text() under 100 ms | Synthetic 220×50 screen timing assertion | Unit | Yes |
| NFR-003 RPC round-trip under 20 ms | Socket microbenchmark with browser stub, 100 iterations | Integration | Yes |
| NFR-004 daemon survives disconnect | Client-disconnect integration test; reconnect assertion | Integration | Yes |
| NFR-005 SIGKILL profile hygiene | SIGKILL E2E fixture + `open()` success assertion | E2E | Yes |
| NFR-006 process death recovery | EOF injection into browser stub; exception type assertion | Integration | Yes |
| NFR-007 socket permissions | `os.stat().st_mode` assertion after daemon bind | Integration | Yes — blocking gate for fix |
| NFR-008 profile directory permissions | `os.stat().st_mode` assertion after create/fork/restore | Unit | Yes — blocking gate for fix |
| NFR-009 MFA file handling | Code review policy (N/A to library code) | — | No |
| NFR-010 Linux x86_64 platform | E2E suite passes on x86_64 CI runner | E2E | Yes |
| NFR-011 Python 3.11 minimum | `python_requires` in pyproject.toml; import test on 3.10 | Unit | Yes |
| NFR-012 1-indexed coordinates | Coordinate return value assertions in ScreenInspector and CarbonylBrowser unit tests | Unit | Yes |
| NFR-013 three-way dispatch symmetry | Mode-parity parameterized test covering all public methods | Integration | Yes — blocking gate |
| NFR-014 no stdout contamination | Subprocess capture of all public methods; assert stdout empty | Integration | Yes |

---

## 7. Risk-Based Prioritization

Test development follows risk order, not component alphabetical order.

**Priority 1 — Security permission gaps (NFR-007, NFR-008)**: These are "Not Met" with no current test. Write the failing assertions first; let them drive the production fix. Risk: credential exposure on multi-user systems.

**Priority 2 — Daemon reconnect and process-death paths (NFR-004, NFR-006, UC-004 E1)**: The highest reliability risk in the system. The daemon's persistence value proposition collapses if reconnect is unreliable. The browser stub fixture must be built before any other integration test.

**Priority 3 — Three-way dispatch symmetry enforcement (NFR-013)**: A silent API gap has already occurred. The mode-parity matrix is the only mechanism that will catch the next one at PR time rather than in production.

**Priority 4 — Performance baselines (NFR-001 through NFR-003)**: Currently asserted by code inspection only. Capture benchmarks before construction changes the implementation, so regressions produce a diff against a known baseline.

**Priority 5 — ScreenInspector and SessionManager full unit coverage**: Lower risk (pure logic, no external state), but highest coverage return on effort. Implement in parallel with Priority 1 and 2.

---

## 8. Acceptance Criteria

A Construction iteration is not releasable unless all of the following pass without exception or waiver:

- [ ] Unit and integration test suites pass in CI with no skipped tests
- [ ] Line coverage meets per-component thresholds in Section 4; no coverage regression from previous iteration
- [ ] NFR-007 and NFR-008 permission assertions pass (requires production `os.chmod` fix to be merged first)
- [ ] NFR-013 mode-parity matrix passes for all public methods in both direct and daemon modes
- [ ] NFR-006 `CarbonylBrowserDead` (or equivalent structured exception) is raised on process-death conditions and asserted in tests
- [ ] Performance baseline artifacts for NFR-001 through NFR-003 are present in CI output (non-blocking on slow runners, but must exist)
- [ ] No open Critical or High defects against the automation layer
- [ ] E2E suite (UC-001 through UC-004 scenarios against local HTTP server) passes before the Construction → Transition gate
- [ ] Bot-detection validation (UC-005) completed manually against at least one Akamai-protected target site and result documented before Transition → Production gate
