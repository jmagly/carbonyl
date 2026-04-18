# Requirements — Trusted Automation

## Functional requirements

Each requirement is traceable to an acceptance test in `04-test-strategy.md` and a workstream issue. The **Repo** column identifies the owning repository.

### FR-1 — Trusted input events (Layer 1)

| ID | Requirement | Repo | Priority |
|----|-------------|------|----------|
| FR-1.1 | Keystrokes dispatched by the agent SDK MUST produce `event.isTrusted === true` at `document.activeElement` | carbonyl | P0 |
| FR-1.2 | Mouse click events MUST produce `event.isTrusted === true` on the target element | carbonyl | P0 |
| FR-1.3 | Mouse-move events MUST produce `event.isTrusted === true` and arrive as a continuous stream preceding any click | carbonyl | P0 |
| FR-1.4 | Agent SDK MUST allow switching between `synthetic` (legacy) and `uinput` (trusted) backends per session | carbonyl + carbonyl-agent | P0 |
| FR-1.5 | Multiple Carbonyl instances on one host MUST NOT crosstalk through shared uinput devices | carbonyl (primitive) + carbonyl-fleet (orchestration) | P1 |

### FR-2 — Fingerprint normalization (Layers 2–3)

| ID | Requirement | Repo | Priority |
|----|-------------|------|----------|
| FR-2.1 | `navigator.webdriver` MUST be `undefined` (not `false`, not `true`) in default agent runs | carbonyl | P0 |
| FR-2.2 | `navigator.plugins` MUST enumerate at minimum PDF Viewer and Chrome PDF Plugin, matching stock Chrome headed | carbonyl | P1 |
| FR-2.3 | `gl.getParameter(UNMASKED_VENDOR_WEBGL)` and `UNMASKED_RENDERER_WEBGL` MUST return values matching a real Chrome installation (not `llvmpipe` / `Mesa`) | carbonyl | P0 |
| FR-2.4 | `Notification.permission` MUST return `"default"` (not `"denied"`) in a fresh profile without a prior prompt | carbonyl | P1 |
| FR-2.5 | `navigator.userAgentData` Client Hints MUST match the configured user-agent string and not report `"Linux"` / `"HeadlessChrome"` | carbonyl | P1 |
| FR-2.6 | User-Agent string MUST NOT contain the `(Carbonyl)` suffix in any agent-facing build | carbonyl | P0 |
| FR-2.7 | `hardwareConcurrency`, `deviceMemory`, screen dimensions MUST report persona-configured values, not Carbonyl defaults | carbonyl-agent (persona) + carbonyl (Blink override) | P1 |

### FR-3 — Behavioral humanization (Layer 4)

| ID | Requirement | Repo | Priority |
|----|-------------|------|----------|
| FR-3.1 | Keystroke inter-key intervals MUST follow a log-logistic (or log-normal) distribution with bigram-dependent timing, configurable per persona | carbonyl-agent | P0 |
| FR-3.2 | Keystroke dwell and flight times MUST fall within human envelopes (dwell 50–200 ms, flight 80–400 ms) with natural variance | carbonyl-agent | P0 |
| FR-3.3 | Mouse trajectories MUST be generated via WindMouse or cubic-Bézier with Fitts's-law-timed traversal | carbonyl-agent | P0 |
| FR-3.4 | ~70% of click movements MUST exhibit overshoot with corrective submovement | carbonyl-agent | P1 |
| FR-3.5 | Slow-motion segments MUST include physiological tremor noise (Gaussian, amplitude inversely proportional to velocity) | carbonyl-agent | P2 |
| FR-3.6 | Every `click(x, y)` call MUST emit preceding `mousemove` events; never a bare click | carbonyl-agent | P0 |
| FR-3.7 | Humanization MUST be disableable via `humanize=False` for testing and deterministic replay | carbonyl-agent | P0 |

### FR-4 — Session & persona management

| ID | Requirement | Repo | Priority |
|----|-------------|------|----------|
| FR-4.1 | Agent SDK MUST expose persona profiles (fast typist, cautious, trackpad vs mouse) as first-class configuration | carbonyl-agent | P0 |
| FR-4.2 | Cookies, localStorage, and IndexedDB MUST persist across agent sessions per-profile | carbonyl-agent + carbonyl (user-data-dir) | P0 |
| FR-4.3 | Fresh profiles MUST be "aged" (warmed with realistic browsing before sensitive-site access) via a documented workflow | carbonyl-agent | P2 |

### FR-5 — Network/TLS fingerprint (Layer 5, deferred to Phase 3)

| ID | Requirement | Repo | Priority |
|----|-------------|------|----------|
| FR-5.1 | JA4/JA4+ TLS fingerprint MUST match a current stable Chrome release within one minor version | carbonyl (Chromium patch) OR carbonyl-agent (proxy intermediary) | P2 |
| FR-5.2 | HTTP/2 SETTINGS frame and pseudo-header order MUST match current Chrome | same as FR-5.1 | P2 |
| FR-5.3 | HTTP/3 QUIC transport parameters MUST match current Chrome | same as FR-5.1 | P3 |

## Non-functional requirements

### NFR-1 — Performance

- Humanization overhead MUST NOT exceed 10% of baseline event-dispatch latency measured end-to-end
- uinput device setup MUST complete in under 100 ms per instance
- Rust-side mouse-path generation MUST sustain 120 Hz event emission without CPU saturation on a 4-core host

### NFR-2 — Operability

- Carbonyl MUST emit a clear, actionable error when `/dev/uinput` is not accessible (permissions, kernel module), naming the specific fix (`modprobe uinput`, add to `input` group, or udev rule)
- Docker deployments MUST have documented `--device=/dev/uinput` + `--group-add` pattern
- Agent SDK MUST expose observability: per-session event counts, humanization profile in use, fingerprint spoofs active

### NFR-3 — Upgrade resilience

- New Chromium patches added to carbonyl MUST be rebaseable onto the next major Chromium version with bounded effort; each patch documented in `MAINTENANCE.md`
- Fingerprint patches SHOULD prefer Blink runtime flag overrides over source modifications where possible, to reduce rebase cost

### NFR-4 — Security

- `/dev/uinput` access MUST be grant-minimized (input group or capability, never CAP_SYS_ADMIN blanket)
- No secrets or credentials MUST be logged when humanization is active (keystroke logs)
- Per-instance uinput devices MUST be cleaned up on process exit (no leaked devices across restarts)

### NFR-5 — Maintainability

- Humanization parameters (timing distributions, mouse algorithm tuning) MUST be data-driven via config files, not hardcoded
- Fingerprint spoof values MUST live in a central profile registry, reloadable without rebuild
- Tests MUST cover each detection layer independently (1–5), plus at least one integrated end-to-end test per reference site (x.com, Cloudflare demo, DataDome demo)

### NFR-6 — Ethics / scope

- The SDK MUST NOT ship with any pre-configured credentials, stolen cookies, or scraped session artifacts
- Documentation MUST clearly state: for operator-authorized automation of own accounts only

## Traceability matrix

Each requirement maps to an acceptance test (`04-test-strategy.md`) and an issue in the issue map (`05-phase-plan.md`). No requirement may be marked complete without both.

## Open requirements (TBD)

- **Client Hints high-entropy values** (model, platformVersion, architecture) — exact values per persona need a design decision. Tracked as research spike in Phase 2.
- **Akamai sensor_data emulation** — whether to attempt, or accept Akamai-protected sites as out of scope. Decision deferred to after Phase 1 validation.
