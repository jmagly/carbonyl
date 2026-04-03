# Carbonyl Automation Layer — User Stories

**Project**: Carbonyl Automation Layer  
**Version**: 1.0  
**Date**: 2026-04-02  
**Status**: Draft

---

## Overview

The Carbonyl Automation Layer is a Python library that wraps a headless Chromium terminal browser
(Carbonyl) to enable web automation with bot-detection bypass, persistent sessions, and
coordinate-based screen interaction. These stories cover two primary personas:

- **Developer/Scripter** — A Python developer writing automation scripts against real websites
- **LLM Agent** — An AI system navigating, inspecting, and interacting with web pages autonomously

---

## Session Management

---

## US-001: Start and Reuse a Named Persistent Browser Session

**As a** Developer/Scripter  
**I want to** start a named browser session once and reconnect to it across multiple script runs  
**So that** I retain cookies, localStorage, and authentication state without re-logging in on every execution

**Acceptance Criteria**:
- [ ] `CarbonylBrowser(session="my-session")` creates a Chromium profile directory the first time it is used
- [ ] On subsequent calls with the same session name, `open()` detects a live daemon via `is_daemon_live()` and reconnects over the Unix socket rather than spawning a new process
- [ ] If no daemon is running, `open()` spawns a fresh browser with `--user-data-dir` pointed at the existing profile, preserving cookies from the previous run
- [ ] `SessionManager.exists()` returns `True` for sessions that have been created and `False` for unknown names
- [ ] `disconnect()` releases the socket connection without terminating the browser process; a subsequent `open()` on the same session reconnects successfully
- [ ] Stale lock files from a previously crashed browser are cleaned automatically via `clean_stale_lock()` before a new browser is spawned

**Story Points**: 5  
**Priority**: Must

---

## US-002: Snapshot Session State Before a Risky Operation

**As a** Developer/Scripter  
**I want to** capture a snapshot of a named session's profile directory before performing a destructive or uncertain action (such as submitting a payment form or accepting a terms dialog)  
**So that** I can restore the browser to a known-good state if the operation fails or produces an unexpected result

**Acceptance Criteria**:
- [ ] `SessionManager` exposes a `snapshot(session_name, snapshot_label)` method that copies the Chromium profile directory to a stamped backup location
- [ ] The snapshot is created while the daemon is live without requiring the browser to be stopped first
- [ ] `SessionManager.list_snapshots(session_name)` returns an ordered list of available snapshots with labels and timestamps
- [ ] `SessionManager.restore_snapshot(session_name, snapshot_label)` stops the running daemon, replaces the profile directory with the snapshot, and leaves the session in a state where a fresh `open()` call will use the restored data
- [ ] If the profile directory is in use by a live daemon and the snapshot write fails, the original profile is not corrupted
- [ ] Snapshots older than a configurable retention period can be purged via `SessionManager.prune_snapshots()`

**Story Points**: 8  
**Priority**: Should

---

## US-003: Recover from Daemon Crash and Re-authenticate

**As a** LLM Agent  
**I want to** detect that a session daemon has crashed mid-task and automatically re-establish the session and re-authenticate  
**So that** a transient process failure does not abort a multi-step workflow that requires login state

**Acceptance Criteria**:
- [ ] `is_daemon_live(session_name)` returns `False` within 2 seconds of the daemon process dying
- [ ] `CarbonylBrowser.reconnect()` returns `False` (instead of raising) when no live daemon is found, allowing the caller to branch into a recovery path
- [ ] Re-opening the session with `open(url)` after a crash spawns a new browser process using the existing profile directory so that persisted cookies are available without a full login
- [ ] If the session was mid-page-load when the crash occurred, the re-spawned browser navigates to the caller-supplied URL rather than restoring the crashed page
- [ ] The `DaemonClient` socket connection raises a typed exception (`DaemonConnectionError`) distinct from a general `OSError` so that recovery logic can target it specifically
- [ ] After successful re-authentication (detected by finding a known logged-in indicator via `find_text()`), the daemon writes a `recovery_ok` log entry

**Story Points**: 5  
**Priority**: Must

---

## Navigation and Interaction

---

## US-004: Navigate to a URL and Wait for the Page to Fully Render

**As a** Developer/Scripter  
**I want to** navigate to a URL and block until the page content is stable in the terminal buffer  
**So that** subsequent `page_text()` or `find_text()` calls see a complete, rendered page rather than a partially loaded state

**Acceptance Criteria**:
- [ ] `browser.open(url)` followed by `browser.drain(seconds)` produces a populated screen buffer after the drain period elapses
- [ ] `navigate(url)` clears the address bar, types the new URL, and presses Enter without leaving residual characters in the URL field
- [ ] After `drain()` completes, `nav_bar_url()` returns a URL that matches the final redirected address (not the original input if a redirect occurred)
- [ ] `drain()` exits cleanly on `pexpect.EOF` so that pages that close the connection immediately do not hang the script
- [ ] A caller-supplied wait time of at least 8 seconds is sufficient to render a typical page at `--fps=5`; this is documented with an example
- [ ] When connected to a daemon, `drain()` delegates to `DaemonClient.drain()` over the Unix socket rather than reading from a local PTY

**Story Points**: 3  
**Priority**: Must

---

## US-005: Click a Button or Link by Finding Its Text on Screen

**As a** LLM Agent  
**I want to** locate a button or link by its visible label text and send a click event to its center coordinate  
**So that** I can interact with page elements without needing to know their pixel positions in advance

**Acceptance Criteria**:
- [ ] `browser.click_text("Sign In")` locates all occurrences of "Sign In" in the raw screen buffer and clicks the center of the first match
- [ ] The returned `(col, row)` tuple is 1-indexed and matches the SGR mouse protocol coordinates consumed by Carbonyl
- [ ] If the text is not found, `click_text()` returns `None` and does not send any mouse events
- [ ] Click is implemented as an SGR press followed immediately by an SGR release (`\x1b[<0;{col};{row}M` / `\x1b[<0;{col};{row}m`) so Carbonyl registers a full click cycle
- [ ] `offset_col` shifts the click point left or right of the text center to target elements like disclosure arrows or icons adjacent to text labels
- [ ] The method works identically in direct-spawn and daemon-connected modes

**Story Points**: 3  
**Priority**: Must

---

## US-006: Disambiguate Clicks When the Same Text Appears Multiple Times

**As a** LLM Agent  
**I want to** click a specific occurrence of a repeated label (such as "Edit" appearing once per table row) by specifying the row it is expected to be on  
**So that** I target the correct element without misclicking a different instance of the same text

**Acceptance Criteria**:
- [ ] `browser.find_text("Edit")` returns a list with one entry per occurrence, each containing `col`, `row`, and `end_col` (all 1-indexed)
- [ ] `browser.click_at_row("Edit", row=15)` clicks the occurrence of "Edit" found on row 15 and returns `None` if no match exists on that row
- [ ] `find_at_row(text, row)` returns the first match dict for the given row or `None`, independently of any click action
- [ ] When `occurrence=1` is passed to `click_text()`, the second match in document order is clicked instead of the first
- [ ] If two occurrences share the same row, `find_at_row` returns the leftmost one (lowest `col` value)
- [ ] All coordinate values returned are compatible with `click(col, row)` without adjustment

**Story Points**: 2  
**Priority**: Must

---

## US-007: Fill a Form Field by Clicking, Typing, and Submitting

**As a** Developer/Scripter  
**I want to** locate a form field by its label or placeholder text, click to focus it, type the field value, and then submit the form  
**So that** I can automate multi-field data entry workflows such as login, search, or checkout forms

**Acceptance Criteria**:
- [ ] `browser.click_text("Username")` or `browser.click_at_row("Username", row=N)` moves focus to the input field
- [ ] `browser.send("alice@example.com")` sends the string as UTF-8 keystrokes to the focused field
- [ ] `browser.send_key("tab")` advances focus to the next field (e.g., from username to password)
- [ ] `browser.send_key("enter")` submits the form without requiring a separate click on the submit button
- [ ] The full sequence (click + send + tab + send + enter) completes a two-field login form when followed by `drain()` for page load
- [ ] `send_key()` raises `ValueError` with the list of valid keys when an unrecognised key name is supplied, rather than silently doing nothing

**Story Points**: 3  
**Priority**: Must

---

## Screen Inspection

---

## US-008: Get a Coordinate-Annotated View of the Screen for Click Targeting

**As a** LLM Agent  
**I want to** retrieve the current screen state as a text grid with row and column rulers overlaid  
**So that** I can reason about element positions and determine accurate click coordinates without guessing

**Acceptance Criteria**:
- [ ] `browser.inspector()` returns a `ScreenInspector` instance populated from the current `raw_lines()` snapshot
- [ ] `si.render_grid()` produces a multi-line string with a two-row column ruler header (tens digit above ones digit) and a `NNNN │` row-number prefix on every content line
- [ ] Ruler tick marks appear at every 10th column by default; the interval is configurable via `ruler_every`
- [ ] `si.print_grid(marks=[(col, row)])` overlays a `●` character at the specified 1-indexed coordinate without modifying the underlying buffer
- [ ] `si.crosshair(col, row, radius=3)` renders only the ±3-row, ±12-column window around the target point, reducing output size for agent prompts
- [ ] `si.dot_map()` overlays a regular grid of `·` markers at configurable column and row intervals across the full screen to help calibrate coordinate estimates

**Story Points**: 3  
**Priority**: Must

---

## US-009: Find Text in the Raw Screen Buffer with Exact 1-Indexed Coordinates

**As a** LLM Agent  
**I want to** search for a text string across the terminal screen buffer and receive all match positions in 1-indexed `{col, row, end_col}` format  
**So that** I can pass coordinates directly to `click()` or use them to reason about element layout without coordinate conversion

**Acceptance Criteria**:
- [ ] `browser.find_text("Submit")` searches the raw terminal buffer (including block/rendering characters not visible in `page_text()`) and returns every match
- [ ] Each result dict contains `col` (start, 1-indexed), `row` (1-indexed), and `end_col` (last character position, 1-indexed, inclusive)
- [ ] Results are ordered top-to-bottom, left-to-right (ascending row, then ascending col within a row)
- [ ] `ScreenInspector.find()` produces the same coordinate format and the same results as `browser.find_text()` for identical input
- [ ] Searching for a string not present on screen returns an empty list, not `None` or an exception
- [ ] Overlapping matches are all reported (e.g., searching "aa" in "aaa" returns two matches at col 1 and col 2)

**Story Points**: 2  
**Priority**: Must

---

## US-010: Inspect a Specific Region to Detect Interactive Elements

**As a** LLM Agent  
**I want to** examine a bounded rectangular region of the screen and receive a structured summary of its text content and detected interactive element types  
**So that** I can determine whether a region contains an input field, button, checkbox, or URL before deciding which interaction to apply

**Acceptance Criteria**:
- [ ] `si.summarise_region(col_start, row_start, col_end, row_end)` returns a dict with `col_range`, `row_range`, `lines`, `text`, and `indicators` keys
- [ ] `indicators` is a list that may contain any combination of `"checkbox"`, `"input_field"`, `"button"`, and `"url"` based on heuristic pattern matching in the region text
- [ ] `"button"` is detected when the region text contains case-insensitive keywords: `sign in`, `submit`, `continue`, `next`, `login`, `search`, or `apply`
- [ ] `"input_field"` is detected when block characters (`▌`, `█`, `░`) or angle-bracket markers are present in the region
- [ ] `"checkbox"` is detected when the pattern `[ ]` or `[X]` appears in the region text
- [ ] `si.annotate(regions=[(c1,r1,c2,r2)])` renders the region with bracket markers (`[` and `]`) at the boundary columns and returns the output as a string suitable for embedding in an LLM prompt

**Story Points**: 3  
**Priority**: Should

---

## Bot Detection and Advanced

---

## US-011: Access an Akamai-Protected Site Without Triggering Server-Side Block

**As a** Developer/Scripter  
**I want to** request pages from sites protected by Akamai Bot Manager without receiving a block page or CAPTCHA  
**So that** my automation can retrieve real page content from sites that use behavioral bot detection

**Acceptance Criteria**:
- [ ] The User-Agent sent in HTTP requests is the configured Firefox UA string (`Mozilla/5.0 (X11; Linux x86_64; rv:122.0) Gecko/20100101 Firefox/122.0`), not a Chromium or Carbonyl-branded string
- [ ] `navigator.userAgent` evaluated in the page JavaScript context returns the same Firefox UA (the `--user-agent` flag overrides both the HTTP header and the JS property)
- [ ] HTTP/2 is disabled via `--disable-http2`, falling back to HTTP/1.1, removing the Chromium SETTINGS frame fingerprint that Akamai's server-side classifier uses
- [ ] `--disable-blink-features=AutomationControlled` is applied so `navigator.webdriver` evaluates to `false` or `undefined` in page scripts
- [ ] `--no-first-run`, `--disable-sync`, and `--password-store=basic` suppress Chromium dialogs and sync traffic that could produce detectable non-browser request patterns
- [ ] When using the Docker fallback, the flags already baked into the image entrypoint are not duplicated on the command line

**Story Points**: 5  
**Priority**: Must

---

## US-012: Send Mouse-Movement Events During Page Load to Satisfy Sensor Entropy

**As a** LLM Agent  
**I want to** emit a sequence of realistic mouse-movement events across the page while it loads  
**So that** bot-detection sensors that require mouse-entropy signals before accepting interaction do not flag the session as a bot

**Acceptance Criteria**:
- [ ] `browser.mouse_move(col, row)` sends a single SGR button-32 sequence (`\x1b[<32;{col};{row}M`) that Carbonyl translates into a DOM `mousemove` event
- [ ] `browser.mouse_path(points, delay=0.05)` iterates through a list of `(col, row)` waypoints and calls `mouse_move()` at each, sleeping `delay` seconds between moves to produce organic-looking telemetry
- [ ] `mouse_move()` and `mouse_path()` delegate to `DaemonClient.mouse_move()` when connected to a daemon so the events reach the live browser process
- [ ] A mouse path interleaved with `drain()` calls between waypoints allows events to be delivered while the page is actively rendering
- [ ] Waypoints are expressed in terminal cell coordinates (1 to `COLS` for col, 1 to `ROWS` for row); values outside this range are accepted without error and clamped or ignored by Carbonyl
- [ ] Calling `mouse_path()` with an empty list completes without error and sends no events

**Story Points**: 3  
**Priority**: Must

---

## US-013: Render a Dot Map to Calibrate Click Coordinates on an Unfamiliar Page

**As a** LLM Agent  
**I want to** overlay a uniform grid of reference markers on the screen at known coordinate intervals  
**So that** I can triangulate the position of any visible element relative to the nearest reference dot before issuing a click

**Acceptance Criteria**:
- [ ] `si.dot_map(step_col=20, step_row=5)` renders the full screen with `·` characters at every 20th column and every 5th row
- [ ] The output includes the two-row column ruler header and `NNNN │` row prefixes consistent with `render_grid()` output
- [ ] `step_col` and `step_row` are independently configurable so agents can increase density in crowded regions or reduce it on sparse pages
- [ ] Dot positions in the rendered output are 1-indexed and match the coordinates that would be passed to `click(col, row)` without adjustment
- [ ] The dot map does not mutate the underlying `ScreenInspector` state; a subsequent `render_grid()` call on the same instance shows no dots
- [ ] The method returns the dot map as a string; `print_grid()` is not called internally

**Story Points**: 2  
**Priority**: Could

---

## US-014: Observe the Current Browser State Without Changing the URL

**As a** LLM Agent  
**I want to** attach to a running daemon session to read the screen and inspect element positions without triggering a navigation  
**So that** I can audit the current page state at any point in a workflow without disrupting it

**Acceptance Criteria**:
- [ ] `browser.reconnect()` connects to the live daemon socket for the session and returns `True` without issuing a `navigate` command
- [ ] After `reconnect()`, `browser.page_text()`, `browser.find_text()`, and `browser.raw_lines()` return data from the currently displayed page
- [ ] `browser.nav_bar_url()` returns the URL currently shown in the Carbonyl address bar, not the URL the session was originally opened with
- [ ] Calling `reconnect()` on a `CarbonylBrowser` instance with no `session` argument returns `False` immediately
- [ ] `reconnect()` does not spawn a new browser process; if no daemon is running, it returns `False` and leaves the browser state unchanged
- [ ] After `reconnect()`, calling `navigate(url)` sends the navigation command over the existing socket without re-spawning

**Story Points**: 2  
**Priority**: Should

---

## US-015: Run the Browser via Docker When No Local Binary Is Available

**As a** Developer/Scripter  
**I want to** run automation scripts on a machine that does not have the Carbonyl binary compiled for its platform by transparently falling back to the Docker image  
**So that** I can use the full automation API on any system with Docker installed without a build step

**Acceptance Criteria**:
- [ ] When `_local_binary()` returns `None`, `open()` automatically constructs a `docker run --rm -it fathyb/carbonyl` command with the supplied URL
- [ ] If a named session is active, the profile directory is mounted into the container at `/data/profile` and `--user-data-dir=/data/profile` is appended to the Carbonyl flags
- [ ] The `_HEADLESS_FLAGS` constants (user-agent override, HTTP/2 disable, etc.) are not duplicated on the Docker command line because they are already included in the image entrypoint
- [ ] The `pexpect.spawn` child process wraps `bash -c "docker run ..."` so that the PTY and screen-buffer machinery functions identically to the local binary path
- [ ] If `docker` is not in `PATH`, `pexpect.spawn` raises a clear `FileNotFoundError` rather than a cryptic timeout
- [ ] Switching between local binary and Docker fallback requires no changes to calling code; the `CarbonylBrowser` API surface is identical in both modes

**Story Points**: 3  
**Priority**: Should

---

## Story Summary

| ID      | Title                                                              | Persona              | Area               | Points | Priority |
|---------|--------------------------------------------------------------------|----------------------|--------------------|--------|----------|
| US-001  | Start and reuse a named persistent browser session                 | Developer/Scripter   | Session Management | 5      | Must     |
| US-002  | Snapshot session state before a risky operation                    | Developer/Scripter   | Session Management | 8      | Should   |
| US-003  | Recover from daemon crash and re-authenticate                      | LLM Agent            | Session Management | 5      | Must     |
| US-004  | Navigate to a URL and wait for the page to fully render            | Developer/Scripter   | Navigation         | 3      | Must     |
| US-005  | Click a button or link by finding its text on screen               | LLM Agent            | Navigation         | 3      | Must     |
| US-006  | Disambiguate clicks when the same text appears multiple times      | LLM Agent            | Navigation         | 2      | Must     |
| US-007  | Fill a form field by clicking, typing, and submitting              | Developer/Scripter   | Navigation         | 3      | Must     |
| US-008  | Get a coordinate-annotated view of the screen for click targeting  | LLM Agent            | Screen Inspection  | 3      | Must     |
| US-009  | Find text in the raw screen buffer with exact 1-indexed coords     | LLM Agent            | Screen Inspection  | 2      | Must     |
| US-010  | Inspect a specific region to detect interactive elements           | LLM Agent            | Screen Inspection  | 3      | Should   |
| US-011  | Access an Akamai-protected site without triggering server-side block | Developer/Scripter | Bot Detection      | 5      | Must     |
| US-012  | Send mouse-movement events during page load to satisfy sensor entropy | LLM Agent          | Bot Detection      | 3      | Must     |
| US-013  | Render a dot map to calibrate click coordinates on an unfamiliar page | LLM Agent          | Screen Inspection  | 2      | Could    |
| US-014  | Observe the current browser state without changing the URL         | LLM Agent            | Session Management | 2      | Should   |
| US-015  | Run the browser via Docker when no local binary is available       | Developer/Scripter   | Navigation         | 3      | Should   |

**Total stories**: 15  
**Total story points**: 51  
**Must**: 9 stories (30 points)  
**Should**: 5 stories (16 points)  
**Could**: 1 story (2 points) (not yet: 0)
