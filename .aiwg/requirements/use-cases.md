---
project: Carbonyl Automation Layer
document-type: Use Case Specifications
status: DRAFT
author: requirements-documenter
created: 2026-04-02
version: 0.1
---

# Use Case Specifications — Carbonyl Automation Layer

## Actors

| Actor | Type | Description |
|-------|------|-------------|
| Automation Script | Primary | Human-written Python code driving browser actions |
| LLM Agent | Primary | AI system issuing automation commands programmatically |
| Daemon Process | System | Persistent headless Chromium process managed by the library |
| Web Application | External | Target website or web app being automated |

---

## UC-001: Execute Authenticated Web Session

**Primary Actor**: Automation Script, LLM Agent

**Trigger**: Script opens a named session and must reach an authenticated state on a target website.

**Preconditions**:
- Carbonyl daemon binary is installed and on PATH
- Target site login URL is known
- Credentials (username and password) are available to the calling script
- Named session profile directory is writable

**Main Success Scenario**:
1. Script calls `SessionManager` with a named profile identifier
2. Library checks whether a matching daemon process is already live (`is_daemon_live()`)
3. If no live daemon exists, library spawns a new daemon process bound to the named profile directory
4. If a live daemon exists, library reconnects to it and skips spawn
5. Script instructs the browser to navigate to the target login URL
6. Script calls `find_text(username_label)` to locate the username field by its visible label; receives `{col, row}` coordinates
7. Script calls `click_at_row()` or `click_text()` to focus the username field, then sends keystrokes to enter the username
8. Script repeats steps 6-7 for the password field
9. Script calls `find_text("Sign In")` (or equivalent button label) to locate the submit button
10. Script calls `click_text("Sign In")` to submit credentials
11. Script calls `drain()` to wait for page transition to complete
12. Script calls `page_text()` and inspects the result to verify an authenticated indicator is present (e.g., user display name, dashboard heading)
13. Session cookies are automatically persisted to the named profile directory

**Extensions**:

**E1 — MFA Required (email code)**:
- After step 11, `page_text()` contains an MFA challenge indicator
- Script calls `find_text("Email")` to locate the email MFA option and clicks it
- Script calls `click_text("Continue")` to request the code
- Script polls a known file path (or environment-provided path) until an MFA code appears
- Script enters the code into the detected code input field
- Script clicks Submit and calls `drain()` to wait for authenticated redirect
- Flow resumes at step 12

**E2 — Navigation Failure**:
- At step 5, browser fails to load the login URL within the configured timeout
- Library raises a timeout exception
- Script logs the failure and retries navigation up to a configurable retry limit before propagating the error

**E3 — Login Credentials Rejected**:
- At step 12, `page_text()` does not contain an authenticated indicator and contains an error message
- Script raises an `AuthenticationError` with the observed page text
- Session profile is not written with invalid-state cookies

**Postconditions**:
- Browser is positioned at the post-login URL of the target application
- Authenticated session cookies are persisted in the named profile directory
- Subsequent runs reconnecting to this profile start in an authenticated state without re-entering credentials (until cookie expiry)

**Related NFRs**:
- NFR-PERF-001: Login sequence completes within 10 seconds on a standard network connection
- NFR-SEC-001: Credentials must not be logged or written to disk by the library
- NFR-REL-001: Daemon reconnect must succeed within 2 seconds when daemon is live

---

## UC-002: Extract Page Data via Screen Inspection

**Primary Actor**: Automation Script, LLM Agent

**Trigger**: Script or agent needs to read structured data from a rendered page (e.g., table values, form state, status text).

**Preconditions**:
- An active session exists with a live daemon process
- Browser has navigated to the page containing the target data
- Page has had sufficient time to begin rendering (or `drain()` will be called to ensure this)

**Main Success Scenario**:
1. Script calls `drain()` to block until the browser render buffer stabilizes and the page is fully painted
2. Script calls `inspector()` to obtain a `ScreenInspector` object bound to the current render buffer snapshot
3. Script calls `ScreenInspector.render_grid(row_start, row_end, col_start, col_end)` to retrieve a character-grid representation of the target region; optionally passes a `marks` list to annotate coordinates
4. Script calls `find_text(target_string)` to locate known anchor text and receive its `{col, row}` position
5. Script uses the anchor coordinates from step 4 to derive relative offsets for adjacent data fields
6. Script calls `raw_lines(row_start, row_end)` to obtain unformatted terminal lines for the relevant row range when character-precise extraction is needed
7. Script parses the returned line strings into structured data (e.g., splits on whitespace, extracts numeric fields)
8. Extracted data is returned to the caller or passed to the LLM agent for further processing

**Extensions**:

**E1 — Target Content Below the Visible Fold**:
- At step 3, `render_grid()` does not contain the expected content
- Script sends scroll keystrokes (`space`, `arrow_down`, or page-down key) via the input API
- Script calls `drain()` to allow the page to re-render after scroll
- Script calls `inspector()` again to obtain a fresh snapshot
- Flow resumes at step 3

**E2 — Dynamic Content Not Yet Rendered**:
- At step 1, `drain()` returns but target data is absent (JS-rendered content still loading)
- Script implements a polling loop: call `inspector()`, check for expected anchor text via `find_text()`, sleep briefly, repeat
- Loop exits on success or after a configurable maximum wait time, raising a `RenderTimeoutError` on failure

**E3 — Ambiguous Text Match**:
- At step 4, `find_text()` returns multiple positions for the same string
- Script uses row/column range constraints in `render_grid()` to narrow the search region
- If ambiguity persists, script uses `raw_lines()` on the known row range and applies regex to isolate the correct match

**Postconditions**:
- Caller has a structured representation of the target page data
- Browser and daemon state are unchanged (inspection is read-only)
- No side effects on the target Web Application

**Related NFRs**:
- NFR-PERF-002: `drain()` must resolve within 5 seconds for standard page loads
- NFR-PERF-003: `render_grid()` and `raw_lines()` must return within 200ms for any valid coordinate range
- NFR-REL-002: Inspection operations must be idempotent; repeated calls on the same snapshot return identical results

---

## UC-003: Perform Targeted Click Operation

**Primary Actor**: LLM Agent

**Trigger**: Agent determines it must activate a specific UI element (button, link, input field) on the current page.

**Preconditions**:
- An active session exists with a live daemon process
- Browser is on the page containing the target element
- The target element is visible within the current viewport (or agent has scrolled to it)

**Main Success Scenario**:
1. Agent calls `find_text(label)` with the visible text label of the target element; receives `{col, row}` coordinates
2. Agent calls `ScreenInspector.render_grid()` with a bounded region centered on the returned coordinates, passing the coordinates as a `marks` entry to visually confirm element position in the grid output
3. Agent inspects the annotated grid to confirm the mark falls on the intended element and not an adjacent one
4. Agent calls `click_text(label)` to click the element identified by label (library resolves coordinates internally)
5. Agent calls `drain()` to wait for any resulting navigation or DOM mutation to complete
6. Agent calls `page_text()` to verify the page state reflects the expected outcome of the click (e.g., modal opened, form submitted, navigation occurred)

**Extensions**:

**E1 — Duplicate Label on Page (Disambiguation Required)**:
- At step 4, the label appears more than once in the visible buffer
- Agent calls `click_at_row(label, row)` passing the specific row number obtained in step 1 to target the correct instance

**E2 — Element Not Locatable by Text**:
- At step 1, `find_text()` returns no match (element is icon-only, image-based, or outside character-rendered area)
- Agent calls `crosshair(col, row)` with an estimated position to display a crosshair overlay confirming the coordinate
- Agent calls `dot_map()` to obtain a spatial map of clickable regions near the estimate
- Agent calls `click(col, row)` directly with the triangulated coordinates
- Flow resumes at step 5

**E3 — Click Has No Visible Effect**:
- At step 6, `page_text()` shows no change from pre-click state
- Agent re-inspects with `inspector()` to determine whether the element is disabled, obscured, or requires a double-click
- Agent retries with appropriate interaction (double-click variant or scroll-to-element) up to a configurable retry limit

**Postconditions**:
- The target UI element has received a click event
- Page state reflects the expected post-click condition (navigation, modal, state change)
- Daemon and session state are updated to reflect the new page context

**Related NFRs**:
- NFR-PERF-004: Click-to-drain cycle must complete within 3 seconds for standard DOM interactions
- NFR-USE-001: `find_text()` must return coordinates within the terminal grid coordinate space documented in the API reference, with no ambiguity in the coordinate system
- NFR-REL-003: Click operations must be deterministic given the same buffer state; identical calls must produce identical coordinates

---

## UC-004: Maintain Persistent Browser Session

**Primary Actor**: Automation Script

**Trigger**: Script completes a run and needs to preserve session state so a subsequent run can resume without re-authentication or loss of in-progress application state.

**Preconditions**:
- An active session exists with a live daemon process that has been used for at least one automation task
- Named profile directory for the session is accessible and writable
- The host process running the daemon has not been terminated

**Main Success Scenario**:
1. Script completes its automation tasks for the current run
2. Script calls `disconnect()` on the session object, which closes the library's connection to the daemon without terminating the daemon process itself
3. Daemon process continues running in the background, maintaining browser state (cookies, DOM, JS heap) bound to the named profile
4. Script process exits normally
5. At the start of the next run, a new script instance calls `SessionManager` with the same named profile identifier
6. Library calls `is_daemon_live()` and receives `True`
7. Library reconnects to the existing daemon process
8. Script calls `page_text()` or `inspector()` to confirm it is at the expected page with session state intact
9. Script proceeds with automation tasks without re-authentication

**Extensions**:

**E1 — Daemon Has Crashed Between Runs**:
- At step 6, `is_daemon_live()` returns `False`
- Library spawns a new daemon process bound to the same named profile directory
- Persisted cookies from the profile are loaded by the new daemon automatically
- Script navigates to the target URL and calls `page_text()` to verify whether cookies are sufficient for silent re-authentication
- If session cookies have expired, script falls back to UC-001 (Execute Authenticated Web Session)

**E2 — Snapshot Before Risky Operation**:
- Prior to a step that may corrupt application state (e.g., a form submit that cannot be undone), script calls `SessionManager.snapshot()` to persist a point-in-time copy of the profile directory
- If the operation produces an unexpected result, script calls `SessionManager.restore(snapshot_id)` to roll the profile back to the pre-operation state
- Daemon is restarted against the restored profile

**E3 — Profile Directory Conflict**:
- At step 7, two script instances attempt to reconnect to the same named profile simultaneously
- Library detects the conflict via a lock file in the profile directory and raises a `ProfileLockError`
- Calling script waits for the lock to be released or fails with a clear error message

**Postconditions**:
- Daemon process is running and holds the full browser session state in memory
- Named profile directory contains the latest persisted cookies and storage data
- Next script run can reconnect and access authenticated pages without user interaction

**Related NFRs**:
- NFR-REL-004: Daemon must remain live across script process exits for a minimum of 24 hours absent host reboot
- NFR-REL-001: Daemon reconnect must succeed within 2 seconds when daemon is live
- NFR-PERF-005: `is_daemon_live()` must resolve within 500ms
- NFR-SEC-002: Profile directory must not be world-readable; library must set permissions to owner-only (mode 0700) on creation

---

## UC-005: Bypass Bot Detection on Target Site

**Primary Actor**: Automation Script

**Trigger**: A target site protected by bot-detection infrastructure (e.g., Akamai Bot Manager) returns an access-denied response or presents a challenge page when the browser navigates to it.

**Preconditions**:
- Automation Script has identified that the target site employs active bot-detection (JA3 fingerprinting, HTTP/2 fingerprinting, behavioral analysis, or cookie-based challenges)
- Carbonyl daemon is not yet launched for this session
- The specific fingerprint vectors relevant to the target site have been researched (UA string, HTTP version, TLS profile, mouse event requirements)

**Main Success Scenario**:
1. Script configures the daemon launch parameters: Firefox User-Agent string, `--disable-http2` flag to force HTTP/1.1 (matching expected Firefox TLS + HTTP fingerprint)
2. Script spawns the daemon with the configured parameters via `SessionManager`
3. Browser navigates to the target site
4. Site's server-side detection evaluates the TLS/JA3 fingerprint and HTTP version; both match the declared Firefox profile, so the initial request is accepted
5. Site delivers the page and executes its JavaScript sensor payload in the browser
6. Script calls `mouse_path()` to inject a series of synthetic mouse movement events following a human-like trajectory across the viewport
7. Akamai JS sensor collects the mouse event data and validates it against behavioral heuristics
8. Akamai sets the `_abck` validation cookie with a passing value
9. Script calls `drain()` to allow any post-validation redirects or DOM updates to complete
10. Script calls `page_text()` to confirm the target page content is accessible (no "Access Denied" text present)
11. Automation proceeds with the full set of page interaction use cases (UC-002, UC-003)

**Extensions**:

**E1 — Access Denied Persists After Fingerprint Alignment**:
- At step 10, `page_text()` still contains an access-denied indicator
- Script logs the full response headers and the current `_abck` cookie value for diagnostic purposes
- Engineering team researches additional fingerprint vectors (canvas fingerprint, WebGL, audio context) that may be evaluated by the sensor
- If the vector requires protocol-level changes, a TLS proxy is evaluated as an intermediate layer to further align the TLS fingerprint
- This extension exits to a manual investigation step; no automated retry

**E2 — Mouse Path Insufficient (Behavioral Score Too Low)**:
- At step 8, `_abck` cookie is set but the sensor assigns a low confidence score (detectable by cookie value structure)
- Script augments the mouse path: increases path length, varies velocity, introduces micro-pauses
- Script re-triggers the sensor evaluation by calling `mouse_path()` with the refined trajectory
- Flow resumes at step 9

**E3 — HTTP/2 Required by Downstream CDN**:
- At step 1, research indicates the site CDN requires HTTP/2 despite bot-detection preferring HTTP/1.1
- Script omits `--disable-http2` and instead configures a matching HTTP/2 SETTINGS frame fingerprint via available Chromium flags
- Flow resumes at step 2

**Postconditions**:
- Browser holds a valid `_abck` cookie (or equivalent bot-detection token) for the target site
- All subsequent navigation requests within the session are treated as human-origin by the bot-detection layer
- Session profile persists the validation cookies so reconnects (UC-004) do not require re-validation on every run (until cookie expiry)

**Related NFRs**:
- NFR-SEC-003: `mouse_path()` trajectories must be generated with sufficient entropy that they are not identical across sessions; a fixed path is trivially fingerprinted
- NFR-PERF-006: Full bot-detection bypass sequence (steps 1-10) must complete within 30 seconds on a standard connection
- NFR-MAINT-001: Fingerprint configuration parameters (UA string, HTTP version flag, mouse path parameters) must be externally configurable without code changes, to allow rapid response to detection rule updates

---

## Traceability Index

| Use Case | Primary Actors | Key API Surface | Related Use Cases |
|----------|---------------|-----------------|-------------------|
| UC-001 | Automation Script, LLM Agent | `SessionManager`, `find_text()`, `click_text()`, `drain()`, `page_text()` | UC-004 (session reuse), UC-005 (bot-protected sites) |
| UC-002 | Automation Script, LLM Agent | `drain()`, `inspector()`, `render_grid()`, `find_text()`, `raw_lines()` | UC-003 (click after inspect) |
| UC-003 | LLM Agent | `find_text()`, `click_text()`, `click_at_row()`, `click()`, `crosshair()`, `dot_map()`, `drain()` | UC-002 (inspect before click) |
| UC-004 | Automation Script | `SessionManager`, `disconnect()`, `is_daemon_live()`, `snapshot()`, `restore()` | UC-001 (re-auth on expired session) |
| UC-005 | Automation Script | `SessionManager` (launch flags), `mouse_path()`, `drain()`, `page_text()` | UC-001 (auth after bypass), UC-004 (persist bypass cookies) |

---

## Open Questions

| ID | Question | Affects | Status |
|----|----------|---------|--------|
| OQ-001 | What is the exact timeout contract for `drain()`? Is it configurable per-call or global? | UC-002, UC-003, NFR-PERF-002 | OPEN |
| OQ-002 | Does `disconnect()` guarantee a flush of profile cookies to disk before returning? | UC-004 | OPEN |
| OQ-003 | Is `mouse_path()` a blocking call or fire-and-forget? Does it return before or after the sensor evaluates? | UC-005 | OPEN |
| OQ-004 | What lock mechanism does the library use for profile directory access — file lock, PID file, or socket? | UC-004 E3 | OPEN |
| OQ-005 | Is MFA code polling (UC-001 E1) handled by a library utility or is it left entirely to the calling script? | UC-001 | OPEN |
