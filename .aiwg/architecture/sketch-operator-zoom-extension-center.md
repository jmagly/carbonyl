# Architecture Sketch: Operator Zoom and Extensions Center

**Status:** Proposed
**Baseline:** `origin/main` `c0693e12`
**Research:** `@.aiwg/working/issue-planner/research-synthesis.md`

## Zoom path

```text
Views accelerator / native button
        |
        v
OperatorControls command mapping
        |
        v
zoom::PageZoom::Zoom(active WebContents, IN|OUT|RESET)
        |
        v
ZoomController -> HostZoomMap -> renderer/compositor
        |                         |
        |                         +-> native WebView pixels
        +-> observer/label            + terminal pixels
```

The operator layer must reuse Chromium preset stepping and add a direct `//components/zoom` GN dependency. Startup `--zoom` remains a terminal-derived viewport input and is not mutated. A Carbonyl `content::ZoomLevelDelegate` bridges Chromium-compatible host values into the profile `PrefService`; it removes overrides on reset, rejects/corrects corrupt values, and skips durable writes for ephemeral/off-the-record contexts. The orderly-close contract must acknowledge the preference write before reporting shutdown success; the existing cookie/storage callback alone is not sufficient evidence.

Reserved zoom commands use one shared operator dispatch policy across the main page, address field, extensions center, popup, and options widgets. They always target the primary page and are consumed even at a preset bound or after a page crash. Unmodified characters remain normal focused-surface input.

## Extensions center path

```text
Native Extensions button
        |
        v
separate browser-owned Widget/WebContents
        |
        v
registered Carbonyl internal origin + WebUIControllerFactory
        |
        +-> bundled HTML/CSS/JS via WebUIDataSource
        |
        +-> narrow Mojo PageHandler
                 |
                 v
     extended status/details DTO + GetExtensionActions /
     RequestExtensionMutation policy layer
                 |
                 v
        profile-owned ExtensionSystem + prefs
```

The spike must select and prove the exact internal scheme/host supported by the pinned headless embedder. The current M150 candidate is `chrome://carbonyl-extensions/`; `carbonyl://extensions` may be selected only if the spike proves equivalent registration, bindings, process lock, CSP, and navigation behavior without disproportionate content-layer patching.

The manager cannot use its own internal URL as extension-action context. An operator-owned weak/lifetime-safe bridge exposes only the primary page state required by policy. The active page's last committed URL determines effective site access and action state; navigation produces an event-driven refresh, while page crash/close yields an explicit unavailable state. All observations and callbacks are invalidated before manager and `BrowserContext` teardown.

The policy bridge returns an immutable, deterministic DTO that distinguishes requested from accepted API permissions and declared from currently effective host access. Exact scopes may appear only in the trusted details view and never in diagnostics or telemetry. Identity strings are bounded, sanitized, bidi-isolated text.

## Security invariants

- Register the controller factory before navigations can request the internal URL.
- Grant privileged bindings only to the exact internal origin and a dedicated renderer process/lock.
- Bundle all resources; default-deny network, frames, plugins, object, and navigation with a strict CSP.
- Prefer a generated typed Mojo interface over stringly typed `chrome.send` handlers.
- IPC accepts stable IDs/enums only; it never accepts filesystem paths, URLs, scripts, permission sets, or profile selectors from JavaScript.
- Every mutation is reauthorized in browser code through the existing management mode and profile-owned state.
- Treat extension manifest name/description/badge fields as untrusted text: length bound, control-character filtering, bidi isolation, and no HTML interpolation.
- Never expose cookies, storage values, page contents, raw source paths, or unredacted host patterns to logs/telemetry.
- Close the WebUI and child extension surfaces before BrowserContext teardown; drop callbacks after navigation/reload/destruction.
- Action/options surfaces retain a sanitized native owner identity, enforce same-extension top-level navigation before commit, default-deny `window.open`, external redirects, downloads, dialogs, and external handoff, and define bounded sizing, popup `Escape`/focus-loss dismissal, invoker focus restoration, disable/crash behavior, and options-window semantics.

## Rejected shortcuts

- Importing `chrome://extensions`: violates ADR-005's no-`//chrome` boundary and pulls Chrome Profile/UI/services/resources.
- Implementing the manager as a privileged installed extension using `chrome.management`: gives extension code authority over peers and bypasses Carbonyl's narrow browser-owned policy.
- Using a `data:` page plus JavaScript injection: no trustworthy origin or maintainable typed security boundary.
- Live enable/disable/remove: current lifecycle and rollback model is intentionally restart-only.
- Reinterpreting `Ctrl+/-` as window, viewport, device-scale, or terminal zoom.

## Delivery gates

1. Zoom can proceed independently.
2. WebUI spike proves build/link/runtime/factory/process/CSP/IPC boundaries, the active-page bridge, and the DTO seam, then records an accepted ADR. A no-go returns to architecture review with a bounded native fallback; it does not start implementation automatically.
3. Popup/options hardening proceeds independently as a defect follow-up to #290/#306.
4. Extensions center implementation depends on the accepted spike ADR and popup/options hardening, and retains #290's policy semantics.
5. Full UI acceptance runs only through a fail-closed launcher in isolated Ubuntu 26.04 and Ubuntu 24.04 X11 environments, never Titan's host display/Wayland session.
