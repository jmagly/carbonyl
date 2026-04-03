# Iteration 1 Plan — Carbonyl Automation Layer

**Sprint**: Iteration 1 (2 weeks)
**Goal**: Eliminate the local privilege escalation chain before non-dev deployment and establish the test infrastructure prerequisite that blocks the integration test tier.
**Start**: 2026-04-07
**End**: 2026-04-18

---

## Sprint Goal

Close the three Critical/High security findings (R-001 plaintext credentials, R-003 world-readable MFA delivery, R-005 unauthenticated daemon socket) that together form a complete local attack chain. Alongside the security work, introduce the browser stub seam identified in SAD §10.5 so that subsequent construction iterations can achieve meaningful unit and integration test coverage without a live Chromium process.

---

## Stories

| ID | Story | Points | Priority | Acceptance Criteria |
|----|-------|--------|----------|---------------------|
| S-001 | **Encrypt credentials at rest using OS keyring** | 3 | P1 | Credentials are stored and retrieved via `keyring` library (libsecret/Keychain backend); plaintext `~/.config/usps/credentials` file is not written on new save; existing plaintext file is migrated and removed on first read; `keyring.set_password` / `keyring.get_password` calls are wrapped in a thin credential helper that downstream scripts import; unit test covers round-trip store/retrieve against `keyring`'s in-memory backend. Resolves R-001. |
| S-002 | **Move MFA code delivery off `/tmp`** | 2 | P1 | MFA code file is written to `~/.config/usps/mfa_code` (or equivalent user-private path) using `os.open(..., O_CREAT \| O_EXCL \| O_WRONLY, 0o600)` to prevent TOCTOU race; consuming code deletes the file in a `finally` block; documentation notes the `/tmp` pattern is prohibited for credential delivery on shared systems; NFR-009 acceptance criteria are met. Resolves R-003. |
| S-003 | **Enforce socket file permissions at daemon startup** | 2 | P1 | `_BrowserServer.__init__` calls `os.chmod(sock_path, 0o600)` immediately after the socket file is created by `socketserver.UnixStreamServer.server_bind()`; if the socket path resolves to a world-writable directory (e.g. `/tmp`), the daemon logs a `[carbonyl] WARNING: socket directory is world-writable` message to stderr and refuses to start; a test verifies the socket file has mode `0o600` after daemon startup; NFR-007 acceptance criteria are met. Resolves R-005. |
| S-004 | **Enforce profile and session.json file permissions** | 2 | P1 | `SessionManager.create()` passes `mode=0o700` to all `mkdir` calls for session and profile directories; `_write_meta()` uses `os.open(..., O_CREAT \| O_WRONLY \| O_TRUNC, 0o600)` instead of `Path.write_text()`; `SessionManager.fork()` and `restore()` apply `shutil.copytree()` with a `copy_function` that preserves/enforces `0o700` on directories and `0o600` on files; a test verifies permissions on a freshly created session under `umask 022`. Resolves NFR-008; partially mitigates R-006. |
| S-005 | **Introduce browser stub / pyte.Screen injection seam** | 3 | P2 | `CarbonylBrowser` gains a `from_screen(screen: pyte.Screen)` class method (or `_screen` constructor kwarg) that bypasses PTY spawn and populates the internal buffer directly; `find_text()`, `raw_lines()`, `page_text()`, `click_text()`, `click_at_row()`, and `ScreenInspector` all function correctly when instantiated via this seam; a `tests/fixtures/` directory is created with two representative screen snapshots (login page, results page) as `pyte.Screen` pickles or plain-text buffer files; the seam is documented in a code comment block. Addresses SAD §10.5 testability gap. |
| S-006 | **Unit test suite for screen inspection and coordinate logic** | 3 | P2 | `tests/test_screen_inspector.py` and `tests/test_browser_direct.py` are created using `pytest`; tests use the stub seam from S-005 and cover: `find_text()` returns correct 1-indexed col/row; `click_text()` returns `None` on missing text; `render_grid()` column ruler format; `summarise_region()` indicator detection; `dot_map()` non-mutation; all tests pass without a live Carbonyl process; CI configuration (GitHub Actions or equivalent) runs `pytest` on push; NFR-002 timing assertion is included. |
| S-007 | **Declare `python_requires` and add `pyproject.toml`** | 1 | P3 | A `pyproject.toml` is added under `automation/` (or repo root) declaring `requires-python = ">=3.11"`; attempting to install on Python 3.10 produces a clear version error at install time, not a runtime `TypeError`; `requirements.txt` lists `pexpect`, `pyte`, and `keyring` (added by S-001) with minimum version pins; NFR-011 is fully met. |
| S-008 | **Add three-way dispatch symmetry checklist to `daemon.py`** | 1 | P3 | A comment block is inserted immediately above `_BrowserServer._dispatch()` enumerating the three locations that must be updated for any new browser command: (1) `CarbonylBrowser`, (2) `DaemonClient`, (3) `_BrowserServer._dispatch()`; the test suite from S-006 includes a smoke test that instantiates `DaemonClient` against a live `_BrowserServer` backed by the stub seam and calls every public method, asserting no `KeyError` or missing dispatch branch; NFR-013 acceptance criteria are met. |

---

## Definition of Done

- [ ] All P1 stories complete with tests (S-001 through S-004)
- [ ] No new Critical/High security issues introduced
- [ ] CI passing (pytest, no lint errors)
- [ ] NFR-007 and NFR-008 status updated to "Met" in the NFR register
- [ ] Risk register updated: R-001 and R-005 status moved to "Mitigated"; R-003 status moved to "Mitigated" with a note that NFR-009 enforcement is now a code-review policy item
- [ ] Browser stub seam (S-005) reviewed and merged before S-006 and S-008 begin

---

## Dependencies

- **`keyring` library** (S-001): must be installable in the CI environment; verify `libsecret` or `SecretService` D-Bus is available on the Linux CI runner, or configure `keyrings.alt` as a fallback backend for headless environments.
- **`pytest`** (S-006): not currently in `requirements.txt`; add to a `requirements-dev.txt` or `pyproject.toml` dev-dependencies group.
- **S-005 before S-006 and S-008**: the stub seam is a prerequisite for both test stories; these should not begin until S-005 is merged.
- **No dependency on upstream Carbonyl changes**: all stories operate entirely within `automation/` and do not require upstream binary updates.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `keyring` headless CI failure: libsecret D-Bus unavailable on runner | Medium | Medium | Add `keyrings.alt` as a dev-only fallback; gate on `KEYRING_BACKEND` env var in tests |
| S-003 socket chmod race: `server_bind()` creates the file; a window exists before `chmod` | Low | Medium | Document the race window; note that `umask(0o177)` set before bind eliminates it — preferred over post-bind chmod |
| S-005 stub seam scope creep: trying to make it support daemon mode too | Medium | Low | Scope strictly to direct mode for this iteration; daemon integration test deferred to Iteration 2 |
| Sprint capacity: 4 P1 security stories are independent and can parallelize, but S-003 and S-004 both touch session startup sequence | Low | Low | Assign S-003 and S-004 to different engineers or serialize them with a clear merge order |
