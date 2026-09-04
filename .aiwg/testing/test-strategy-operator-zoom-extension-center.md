# Test Strategy: Operator Zoom and Extensions Center

**Status:** Proposed
**Phase:** Construction
**References:** `@.aiwg/requirements/UC-operator-zoom-extension-center.md`, `@.aiwg/risks/risks-operator-zoom-extension-center.md`

## Test levels

### Unit and model tests

- Accelerator-to-command mapping for OEM plus/equal, shifted plus, keypad add, OEM/keypad minus, main/keypad zero, and rejected near-misses.
- Zoom percentage/model synchronization, reset, min/max, crashed/non-live WebContents, and accessibility state.
- Zoom preference serialization, invalid/corrupt values, default removal, two-site/two-profile isolation, ephemeral profile behavior, and write failure.
- Internal URL/factory allowlist and navigation decisions.
- WebUI DTO serialization with long Unicode, bidi controls, control characters, missing names, malformed values, and deterministic ordering.
- Management-mode capability matrix and stable result codes.

### Contract/build tests

- No new dependency on `//chrome/browser/ui/webui/extensions`, Chrome Profile, Web Store, CRX updater, or unrestricted management APIs.
- All WebUI resources are compiled/bundled; CSP contains no remote source or unsafe dynamic-code allowance.
- Mojo interface permits only list/details/action/options and known-ID restart mutations.
- Existing extension runtime, embedder audit, storage flush, operator controls, and release metadata checks remain green.

### Isolated UI/integration tests

- The launcher fails before browser start unless `CARBONYL_DISPOSABLE_BROWSER_QA=1`, `/etc/os-release` identifies the approved Ubuntu 26.04 baseline or Ubuntu 24.04 compatibility guest, guest-owned Xorg is reachable at `DISPLAY=:99`, `WAYLAND_DISPLAY` is unset, and no Titan host Xauthority, Wayland socket, input device, or GPU endpoint is mounted/inherited.
- Record guest OS, package set, Xorg configuration, XKB layout, candidate commit/runtime hash, artifact origin, preflight outcome, and test result. Each Ubuntu target builds locally or verifies the identical candidate artifact hash before execution.
- Zoom: page/address/extensions/popup/options focus, every key family on US and one non-US XKB layout, preset stepping, reset, min/max repeated keys, shortcut non-leakage, pointer hit testing, resize, terminal progress, and orderly close. Reserved shortcuts always target the main page; unmodified characters stay with the focused surface.
- Persistence: distinguish in-memory mutation, preference-write acknowledgment, orderly-shutdown acknowledgment, process exit, crash before/after acknowledgment, same profile, different profile, same/different host, and ephemeral no-write.
- At 200%, a known fixture must retain reachable controls, visible focus, bounded chrome, correct pointer hit targets, and continuing terminal frames. At 400%, assert the fixture's responsive marker/bounds and no unintended toolbar overflow; screenshots are supplemental only.
- Extensions center: 0/1/5/20 deterministic fixtures; assert ordering, scrolling/reachability, stable focus after updates, policy-specific operations, persistent restart-required state, and no live-registry mutation across narrow/wide windows and enlarged text.
- Hostile metadata/URL fixtures: huge names/badges, bidi controls, markup strings, external navigation, frames, `window.open`, downloads, JavaScript dialogs, renderer crash, and cross-origin IPC attempts.
- Popup/options fixtures assert sanitized native owner identity, pre-commit same-extension top-level navigation, default-deny external/new-window behavior, bounded sizing, popup `Escape` and focus-loss dismissal, focus restoration, parent close, extension disable, manager reload, renderer crash, and `BrowserContext` teardown.

## Required regression evidence

- Existing browser controls, native CSS typography, extension action popup/options, profile transition/persistence, trusted input, resize, terminal rendering, and storage-flush suites pass.
- No browser/display/GPU/input test runs on Titan's host session.
- Runtime size and startup changes from the WebUI spike are recorded before implementation approval.

## Exit criteria

- All unit/contract tests pass with warnings as errors.
- Both isolated Ubuntu targets pass focused acceptance.
- No critical security risk remains open.
- Documentation clearly distinguishes page zoom, startup `--zoom`, viewport, device scale, and window resize.
- Documentation calls the extensions center Carbonyl-owned and does not claim Chrome/Web Store parity.
- The preflight negative suite proves each missing/unsafe isolation signal exits nonzero without launching a browser.
