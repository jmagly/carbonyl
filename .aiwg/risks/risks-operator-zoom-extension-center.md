# Risk Register: Operator Zoom and Extensions Center

| ID | Risk | Likelihood | Impact | Mitigation / acceptance evidence |
|---|---|---:|---:|---|
| R-OZ-01 | Dynamic zoom is implemented by mutating viewport/device scale and breaks pointer or terminal mapping | Medium | High | Use `zoom::PageZoom` only; assert unchanged native bounds/viewport coordinates and working pointer targets. |
| R-OZ-02 | Shortcut variants fail on Linux layouts/keypads or leak to page/extension code | Medium | High | Match Chromium OEM/shift/keypad matrix at high priority; test non-US layout and page key recorder. |
| R-OZ-03 | Claimed host zoom disappears or crosses profiles after restart | Medium | High | Implement a Carbonyl ZoomLevelDelegate/PrefService adapter; require acknowledged preference write and same-profile reload after orderly close; test two hosts, two profiles, corrupt values, and ephemeral no-write. |
| R-OZ-04 | Toolbar additions recreate extension-row overflow | Medium | Medium | Compact accessible controls, responsive layout, narrow-window and 200% text tests. |
| R-EX-01 | WebUI bindings are granted to an ordinary page or extension renderer | Low | Critical | Exact factory/origin/process lock, navigation tests, ordinary-page negative IPC tests. |
| R-EX-02 | Extension-controlled metadata causes XSS, spoofing, bidi confusion, or memory/layout abuse | Medium | High | Text-only rendering, CSP, no remote content, bounds/control filtering/bidi isolation, hostile fixtures. |
| R-EX-03 | WebUI bypasses `unavailable`/`read-only`/`restart` policy | Medium | Critical | Browser-side authorization on every request; narrow ID/enum IPC; mode matrix tests. |
| R-EX-04 | Reusing Chrome UI materially expands dependencies and rebase surface | High | High | Carbonyl-owned minimal controller/resources; measure link/size/patch impact in spike; reject `//chrome` dependency. |
| R-EX-05 | “Load unpacked” silently authorizes copied or attacker-modified profile paths | Medium | Critical | Keep onboarding out of basic UI; external explicit source authorization and a separate threat model. |
| R-EX-06 | WebUI state becomes stale or callbacks outlive navigation/context teardown | Medium | High | Observer/event-driven updates, generation-bound callbacks, close-before-context ordering, crash/reload tests. |
| R-EX-07 | Popup/options content spoofs owner identity, escapes navigation constraints, or survives its owner/context | Medium | High | Native sanitized owner identity; pre-commit same-origin enforcement; default-deny new windows/downloads/dialogs/external handoff; bounded lifecycle/focus/crash tests. |
| R-QA-01 | Native UI testing destabilizes Titan's host display/Wayland session | Medium | Critical | Launcher exits before browser start unless disposable marker, approved Ubuntu guest, owned `DISPLAY=:99`, no Wayland/host sockets, Xauthority/input/GPU endpoints pass the isolation checks. |

## Gate disposition

No unmitigated critical risk is accepted for implementation. R-EX-01, R-EX-03, R-EX-05, and R-QA-01 are executable blocking acceptance conditions. R-EX-07 must close before the center exposes action/options entry points.
