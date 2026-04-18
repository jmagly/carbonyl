# Research Index — Trusted Automation

Consolidated findings from five parallel research tracks (R1–R5). Full outputs archived; this index distills what the SDLC docs depend on.

## R1 — Headless Ozone evdev path (carbonyl repo, Chromium tree)

**Question**: Does Carbonyl's headless Ozone platform read `/dev/input`, or can it be wired to?

**Key findings** (all file:line verified in the Carbonyl tree):

- **Default platform**: `ozone_platform = "headless"` (set in `chromium/src/build/config/ozone.gni:60-62`)
- **Headless implementation uses `StubInputController`** at `chromium/src/ui/ozone/platform/headless/ozone_platform_headless.cc:133`; `CreateSystemInputInjector()` explicitly returns `nullptr` at line 87
- **EVDEV IS PRESENT in the tree** at `chromium/src/ui/events/ozone/evdev/` — fully intact: `EventFactoryEvdev`, `InputControllerEvdev`, `DeviceManager`, `KeyboardEvdev` all present. `BUILD.gn:46` defines the `evdev` component.
- **But evdev is NOT compiled into headless**: headless BUILD.gn never pulls `//ui/events/ozone:evdev`
- **DRM/GBM platform**: exists but `chromium/src/ui/ozone/platform/drm/BUILD.gn:15` asserts `is_chromeos`, not buildable for Linux headless
- **Current injection bypasses Ozone entirely**: `chromium/src/headless/lib/browser/headless_browser_impl.cc:465-609` directly constructs `NativeWebKeyboardEvent` / `blink::WebMouseEvent` and calls `ForwardKeyboardEvent`/`ForwardMouseEvent` on `RenderWidgetHost`. No `ui::Event`, no `PlatformEventSource`
- **`HeadlessPlatformEventSource`** (`ozone_platform_headless.cc:44-53`) is a no-op stub
- **`HeadlessWindowTreeHost::DispatchEvent()`** always returns false

**Implication**: Path (b) from R1 question — wire `EventFactoryEvdev` into the headless platform — is viable. Work consists of:
1. Add `//ui/events/ozone:evdev` to headless BUILD.gn deps
2. Replace `StubInputController` with `InputControllerEvdev` in `OzonePlatformHeadlessImpl::InitializeUI()` (lines 122-138)
3. Instantiate `DeviceManager` scanning `/dev/input`
4. Real `PlatformEventSource`
5. Coexist with the existing FFI callback path (for `--input-mode=synthetic` fallback)

**Unknown**: thread coordination between Carbonyl's Rust FFI callbacks and `EventThreadEvdev`. Resolved via Phase 0 validation spike.

## R2 — Fingerprint inventory (Carbonyl on Chromium M147)

**Key findings**:

- **`navigator.webdriver`**: mitigated via `--disable-blink-features=AutomationControlled` in `automation/browser.py:48`. Status: fix is applied but not validated as default for agent builds
- **User-Agent `(Carbonyl)` suffix**: introduced by patch `chromium/patches/chromium/0004-Setup-browser-default-settings.patch`. Overridden by Firefox UA in `automation/browser.py:55`. Recommendation: remove the suffix from patch 0004 (source-of-truth fix)
- **`navigator.plugins` / `mimeTypes`**: empty (stock headless). UNPATCHED; high-risk tell
- **`window.chrome.runtime`**: absent. UNPATCHED; medium-risk
- **WebGL `UNMASKED_RENDERER_WEBGL`**: reports `llvmpipe` / `Mesa` (software rasterizer). UNPATCHED; critical tell
- **`Notification.permission`**: auto-denies on fresh profile. UNPATCHED
- **`navigator.userAgentData` (Client Hints)**: exposes Linux, no platformVersion spoofing. UNPATCHED
- **HTTP/2 fingerprint**: mitigated via `--disable-http2` CLI flag (forces HTTP/1.1). Blunt; real Chrome uses HTTP/2

**Prioritized mitigation (highest-impact first)**:
1. WebGL spoof (CRITICAL — Chromium patch required)
2. `navigator.plugins` populate (CRITICAL — Chromium patch)
3. Remove UA `(Carbonyl)` suffix (HIGH — patch 0004 edit)
4. `window.chrome.runtime` stub (MEDIUM — content-script injection, faster iteration)
5. `Notification.permission` default (MEDIUM — Chromium patch)

## R3 — Humanization literature (external research with citations)

**Keystroke timing**:
- Log-logistic distribution fits free-text flight-time histograms better than log-normal per Sanchez-Casado et al. 2021 (doi:10.1016/j.heliyon.2021.e08416)
- Two-component mixture (mechanical vs cognitive pauses) is standard
- Bigram timing is a known scorer signal
- Dwell 50–200 ms, flight 80–400 ms are commonly cited human envelopes

**Mouse motion**:
- WindMouse algorithm (Benjamin Land, ~2007) — canonical physics-inspired approach
- Cubic Bézier + Fitts's-law MT + stochastic overshoot — Ghost-Cursor reference implementation (Xetera/ghost-cursor, ~62k weekly npm downloads)
- Fitts's law: `MT = a + b·log2(D/W + 1)` — established HCI
- Minimum-jerk velocity profile — Flash & Hogan 1985
- ~70% of pointing movements overshoot 3–12% then correct (Elliott et al., motor-control literature)

**Scorer signals (input-side only; network covered by R4)**:
- Akamai Bot Manager: encrypted `sensor_data` collects mouse/keystroke/scroll/touch; ML across 50+ features; explicit replay detection
- DataDome / PerimeterX: mouse entropy (Shannon entropy of direction-change), trajectory curvature, dwell/flight distributions
- Cloudflare Turnstile: more passive (browser quirks, WebGL, hardware); some behavioral ML

**Rust crates**:
- `windmouse-rs` exists (direct WindMouse port); partial coverage
- No mature Rust crate covers full stack (timing + motion + overshoot + tremor); Ghost-Cursor (TypeScript) is the reference spec

**Architectural recommendation** (adopted in §02-architecture.md):
- Generation layer: Rust-side, in `carbonyl-agent`
- Policy layer: Python-side, in `carbonyl-agent`
- Persona struct crosses the boundary once per session, not per event

## R4 — Network/TLS fingerprinting (skeleton; citations pending)

Agent returned an uncited skeleton due to missing web-search tools; verification required before Phase 3 commit.

**Skeleton contents**:
- **TLS**: JA3, JA4/JA4+, JA3S; Chromium uses BoringSSL; impersonation SOTA = curl-impersonate (C), uTLS (Go), tls-client (Go wrapper), custom rustls
- **HTTP/2 fingerprint**: Akamai's `SETTINGS;WINDOW_UPDATE;PRIORITY;pseudo-header-order` format (Akamai whitepaper 2017); Chrome specifics: `HEADER_TABLE_SIZE`, `ENABLE_PUSH=0` since ~M106, `INITIAL_WINDOW_SIZE=6291456`, pseudo-header `:method :authority :scheme :path`
- **Detection vendors**: Cloudflare, Akamai, DataDome, PerimeterX, Imperva, Arkose — all correlate TLS + HTTP/2 fingerprints
- **Mitigation options**:
  - BoringSSL patching: invasive, high rebase cost
  - Proxy intermediary (curl-impersonate / uTLS): lower Chromium impact, requires full H2 re-implementation
  - Chrome CLI flags: insufficient; cannot reorder extensions

**Action for Phase 3**: re-dispatch a web-enabled research agent to populate citations before ADR-005.

## R5 — Carbonyl patch inventory (this repo)

**Key findings**:

- **24 patches** tracked in `chromium/patches/chromium/`
- **Carbonyl-specific C++ sources**:
  - `chromium/src/carbonyl/src/browser/renderer.cc` (181 LOC) — Chromium entry
  - `chromium/src/carbonyl/src/browser/bridge.{cc,h}` — DPI/bitmap-mode statics
  - `chromium/src/carbonyl/src/browser/host_display_client.{cc,h}` — Mojo LayeredWindowUpdater
  - `chromium/src/carbonyl/src/browser/render_service_impl.{cc,h}` — Mojo service wiring
- **12 `extern "C"` FFI functions** crossing Rust ↔ C++ (bridge.rs): `carbonyl_bridge_*`, `carbonyl_renderer_*`. No input-related FFI yet beyond existing synthetic callbacks
- **Build**: GN+ninja for Chromium (1–3h Docker full build); Cargo for Rust (~10s). **Incremental Chromium builds not recommended**
- **Rust crate**: single-crate `cdylib`, Edition 2021, minimal deps (libc, unicode-*, chrono). ~2,971 LOC Rust
- **Upgrade cadence**: M147 current; six-phase upgrade from M111 completed April 2026; major-version rebases are high-effort
- **CI**: draft stage; `.gitea/workflows/{check.yml, build-runtime.yml}` exist on a bare runner (policy violation flagged); container-based CI planned
- **No TLS/network customization today** — all network plumbing is stock BoringSSL via CDP

**Implications**:
- New Chromium patches are expensive (rebase tax); prefer flags/content-scripts when possible
- Rust work is cheap to iterate; co-locate humanization there
- FFI surface is stable and well-documented; adding an input-mode enum fits the existing pattern

## Open research items (carried into Phases)

- **Phase 0**: Validate uinput → headless Ozone reaches Blink with `isTrusted: true`
- **Phase 2**: Client Hints high-entropy value tables per persona
- **Phase 3**: Re-run R4 with web search enabled; write ADR-005
- **Phase 3**: Feasibility of BoringSSL patch vs uTLS proxy for HTTP/3/QUIC (harder than H2)

## Research provenance

- R1, R2, R5: code-grounded, file:line references in the Carbonyl tree (verified)
- R3: external literature with URL citations (verified)
- R4: skeleton only (citations pending)
