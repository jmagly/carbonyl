# Use Cases: Operator Zoom and Extensions Center

**Status:** Proposed
**Phase:** Construction planning
**Research:** `@.aiwg/working/issue-planner/research-synthesis.md`

## UC-OZ-001: Adjust page zoom from operator mode

**Actor:** Human operator
**Goal:** Make page content larger or smaller without resizing the window or changing terminal geometry.

### Main flow

1. The operator focuses the Carbonyl operator window.
2. The operator presses `Ctrl++` or `Ctrl+-`, or activates a native zoom control.
3. Carbonyl applies the next Chromium preset page-zoom level to the active page.
4. Browser chrome displays the current percentage without stealing focus.
5. Both the native page and simultaneous terminal output reflect the same zoomed `WebContents`.

### Alternatives

- `Ctrl+0` or the percentage/reset control returns to the profile default.
- At minimum/maximum, the command is consumed but the level does not exceed Chromium's bounds.
- If the page is crashed or cannot be zoomed, controls become unavailable and no unsafe fallback changes geometry.
- With focus in the address field, extensions center, action popup, or options surface, the reserved operator shortcut still targets the main page and is consumed; unmodified `+`, `-`, and `0` remain normal focused-surface input.

### Acceptance

- OEM/shifted and keypad variants work on Ubuntu 24.04 and 26.04 X11, including a supported non-US XKB layout.
- Consumed shortcuts never reach page script, address editing, or extension command handlers.
- Native bounds, viewport contract, device scale, pointer mapping, and terminal cell geometry remain unchanged.
- Zoom values use Chromium-compatible host keys, are profile isolated, and persist after an acknowledged preference write and orderly shutdown when a persistent profile is used. Ephemeral/off-the-record contexts do not write them.
- Reset removes the host override and returns to the configured/default zoom rather than assuming `100%`.

## UC-OZ-002: Open the extensions center

**Actor:** Human operator
**Goal:** Inspect configured extensions in a usable browser-owned interface.

### Main flow

1. The operator activates one native `Extensions (N)` entry point.
2. Carbonyl opens a separate, bounded internal WebUI using the same `BrowserContext`.
3. The page lists configured extensions through an immutable browser-owned DTO: bounded human-readable name and description, version, full ID, state, requested versus accepted API permissions, declared versus currently effective host access, management mode, and action/options availability.
4. The operator can inspect details without exposing secrets to logs or page content.

### Acceptance

- The center works with 0, 1, 5, and 20 extensions, narrow windows, keyboard-only input, and enlarged text.
- The internal origin and trusted header cannot be spoofed by extension content.
- Resources are bundled and same-origin; the page performs no remote fetches.
- Ordinary pages and extension origins cannot call the management IPC.
- Action and host-access state is evaluated against the operator's active page, not the manager's internal URL; navigation, crash, close, and profile teardown cannot leave a stale page pointer.

## UC-OZ-003: Stage an allowed extension state change

**Actor:** Human operator
**Precondition:** Management mode is `restart`; the extension source was already authorized at launch.

### Main flow

1. The operator chooses enable, disable, or remove-on-restart.
2. The WebUI sends a typed request containing only the known extension ID and operation.
3. Browser code revalidates mode, ID, profile ownership, and operation.
4. Carbonyl persists restart intent and displays an accessible `Restart required` result.
5. The live registry remains unchanged until orderly restart.

### Alternatives

- `unavailable`: no management data or actions are exposed.
- `read-only`: status/details are available and mutations are disabled with an explanation.
- Unknown ID, stale page, policy denial, or failed persistence returns a stable error without partial mutation.

## Non-goals

- Chrome/Web Store parity or loading Chrome's `chrome://extensions` implementation.
- Remote/CRX installation, update checks, native messaging, arbitrary file browsing, or profile scanning.
- General `chrome.management` access for installed extensions.
- Broad `tabs`, `webNavigation`, or `commands` compatibility; those remain under #156.
