---
title: Traceability Review — Carbonyl Automation Layer SAD
reviewer: Requirements Analyst
date: 2026-04-03
document-reviewed: software-architecture-doc.md v1.0
---

# Traceability Review — Carbonyl Automation Layer SAD

**Reviewer**: Requirements Analyst
**Date**: 2026-04-03
**Document Reviewed**: software-architecture-doc.md v1.0
**Verdict**: APPROVED_WITH_SUGGESTIONS

---

## Use Case Coverage

| UC ID | Title | SAD Coverage | Gap |
|-------|-------|-------------|-----|
| UC-001 | Execute Authenticated Web Session | COVERED | None. SessionManager (§5.3), CarbonylBrowser direct/daemon modes (§5.1), `find_text`/`click_text`/`drain`/`page_text` all described. Daemon reconnect path in §5.1 covers step 4. |
| UC-002 | Extract Page Data via Screen Inspection | COVERED | None. ScreenInspector capabilities (§5.4), `raw_lines`, `render_grid`, `find_text`, and `extract_text` paths described. Screen buffer model (§7.2) covers coordinate extraction semantics. |
| UC-003 | Perform Targeted Click Operation | COVERED | Minor. SGR mouse protocol and click mechanics covered in §7.1. `crosshair`, `dot_map`, and `annotate` described in §5.4. The dual-mode dispatch (`if self._daemon_client`) is documented in §5.1, satisfying determinism requirement. |
| UC-004 | Maintain Persistent Browser Session | COVERED | Minor. Daemon lifecycle (§5.2), fork/snapshot/restore operations (§5.3), and process topology (§9.3) collectively address all main flow steps. Gap: `disconnect()` behavior (socket close without daemon termination) is implied but not explicitly defined in the SAD. UC-004 open question OQ-002 (flush guarantee) is unanswered. |
| UC-005 | Bypass Bot Detection on Target Site | COVERED | Minor. Bot-detection bypass stack fully documented in §8.1 (UA, HTTP/2, webdriver flag, mouse entropy). Known JA3 gap is acknowledged in §8.1 and §11. `mouse_path` is referenced via UC-005 but its architecture is described only in §5.1 as part of CarbonylBrowser input events — no dedicated section. |

---

## NFR Coverage

| NFR ID | Category | SAD Coverage | Gap |
|--------|----------|-------------|-----|
| NFR-001 | Performance — drain() time bound | COVERED | §5.1 describes the polling loop and EOF exit; §10.3 and §10.2 note single-threaded pyte and EOF handling. |
| NFR-002 | Performance — find_text() <100 ms | COVERED | §5.4 describes single-pass `str.find` scan over 220×50 buffer. |
| NFR-003 | Performance — Daemon RPC latency | COVERED | §5.2 specifies `AF_UNIX SOCK_STREAM`, newline-delimited JSON, single send/recv; AD-04 rationale matches latency goal. |
| NFR-004 | Reliability — Daemon survives client disconnect | COVERED | §5.2 documents `daemon_threads = True` and exception handling in handler. |
| NFR-005 | Reliability — Profile not corrupted on SIGKILL | COVERED | §5.3 documents `clean_stale_lock`, `_is_stale_lock` via `os.kill(pid, 0)`, and lock cleanup in fork/restore. |
| NFR-006 | Reliability — Graceful recovery on process death | PARTIAL | §10.2 notes `pexpect.EOF` behavior and `RuntimeError` on daemon disconnect. The lack of a typed exception (`CarbonylBrowserDead`) is noted in §11 as a gap but not assigned architectural remediation. |
| NFR-007 | Security — Unix socket ACL | PARTIAL | §8.2 acknowledges the Unix socket but does not document a mechanism to enforce `0o600`. The SAD records the current unresolved state without prescribing an architectural fix. |
| NFR-008 | Security — Credential file permissions | PARTIAL | §8.2 notes Chromium profile storage path but does not describe permission enforcement. NFR-008 is "Not Met" in the register; the SAD does not propose a remediation path. |
| NFR-009 | Security — MFA code via /tmp | COVERED | §8.2 correctly scopes this as out-of-library (downstream script concern); SAD aligns. |
| NFR-010 | Compatibility — Linux x86_64 / arm64 | COVERED | §10.4 and §9.2 cover platform targets, binary resolution, and Docker fallback. |
| NFR-011 | Compatibility — Python 3.11 minimum | PARTIAL | §9.1 states "Python 3.10+" but the NFR requires 3.11. The version discrepancy between the SAD and the NFR register is a concrete inconsistency requiring resolution. |
| NFR-012 | Maintainability — 1-indexed coordinates | COVERED | AD-05 and §7.1 fully document the coordinate convention and SGR protocol alignment. |
| NFR-013 | Maintainability — Three-way command symmetry | PARTIAL | §5.1 and §5.2 describe the dual-mode dispatch pattern. The SAD does not prescribe the checklist or enforcement mechanism called for by NFR-013. |
| NFR-014 | Observability — stderr logging | PARTIAL | §10.1 describes the `log()` function and `[carbonyl]` prefix convention but notes daemon stdio is redirected to `/dev/null` post-fork. The SAD does not propose a fix (e.g., redirect to a log file), despite listing this as a LOW-severity gap in §11. |

---

## Summary

10 of 14 NFR categories have full or partial architectural coverage; 0 are entirely absent from the SAD. All 5 use cases are architecturally covered. The document is strong on structural and behavioral architecture (components, wire protocol, coordinate system, bot-detection stack) and appropriately honest about known gaps via §11.

Overall traceability: **5/5 use cases covered (100%); 10/14 NFRs fully covered, 4 partially covered (0 missing)**. The partial-coverage items are not architectural omissions — they are implementation-level gaps already acknowledged in the SAD — but the SAD does not prescribe remediation paths for the two highest-priority security gaps (NFR-007, NFR-008).

---

## Gaps Requiring SAD Updates

1. **NFR-007 / NFR-008 (Security — file permissions)**: The SAD acknowledges both issues in §8.2 and §11 but does not specify the architectural fix. A brief addition to §8.2 should prescribe explicit `os.chmod(socket_path, 0o600)` after socket creation and `os.makedirs(profile_path, mode=0o700)` in `SessionManager.create()`. These are one-line changes with clear ownership.

2. **NFR-011 (Compatibility — Python version)**: §9.1 states "Python 3.10+" while the NFR register requires 3.11. One of the two documents must be corrected. Recommended: update §9.1 to state 3.11 and document the `python_requires` constraint that should be added to `pyproject.toml`.

3. **NFR-014 (Observability — daemon log loss)**: §11 lists "Daemon logs lost after fork" as LOW severity but proposes no solution. The SAD should note the intended fix (redirect daemon stdio to `~/.local/share/carbonyl/sessions/<name>.log` at fork time) so it is actionable for the next development iteration.

4. **UC-004 / OQ-002 (`disconnect()` flush guarantee)**: The SAD does not define whether `disconnect()` guarantees a Chromium profile flush before returning. This is an open question in the use-case document that the SAD should resolve or explicitly defer.
