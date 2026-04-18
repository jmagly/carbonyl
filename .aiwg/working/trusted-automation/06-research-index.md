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

## R4 — Network/TLS fingerprinting (superseded)

First pass returned an uncited skeleton. Superseded by R7, R8, R9 below which re-ran with web access and produced citations.

**Correction from R4 skeleton**: the skeleton overstated the importance of TLS-impersonation libraries for Carbonyl specifically. Carbonyl wraps real Chromium and therefore inherits real Chrome's JA4; the libraries are primarily for non-browser scrapers. See R7 for the correction and the new library-choice reasoning.

## R7 — TLS impersonation library comparison (with web citations)

**Recommendation for a Rust-first stack**: `wreq` (formerly `rquest`) primary, `tls-client` (Go) via C shared-lib fallback. Both tracked in ADR-005.

**Comparison summary**:

| Tool | Lang | State (Apr 2026) | Coverage | Rust embed cost |
|------|------|-------------------|----------|-----------------|
| `wreq` / `wreq-util` | Rust | v6.0.0-rc.28, active, solo maintainer | TLS + H2, **no H3** | Native, drop-in |
| `tls-client` (bogdanfinn) | Go | v1.14.0, active | TLS + H2 + H3 | cgo via shared-lib FFI |
| `uTLS` upstream | Go | v1.8.2, active | TLS only (H2/H3 handoff to caller) | cgo; also underlies tls-client |
| `curl-impersonate` (lwthiker) | C | Dead since 2024 (last release Mar 2024, Chrome 116) | TLS + H2 | libcurl FFI, but stale |
| `curl-impersonate` (lexiforest fork) | C | Active v8.15.0, Chrome 145/146 | TLS + H2 + H3 via `curl_cffi` 0.15 | FFI, heavy |
| `specters` | Rust | Active, smaller surface | TLS Chrome 142–146 | Native |
| `cloudflare/boring` | Rust | Active | Raw BoringSSL; DIY fingerprints | Native, owned-profile path |
| mitmproxy addons | Python | No Chrome-impersonating addon maintained | — | Not viable |

**Key citations**:
- [refraction-networking/utls](https://github.com/refraction-networking/utls) — upstream primitive
- [bogdanfinn/tls-client](https://github.com/bogdanfinn/tls-client) — Go lib with C shared-lib binding
- [0x676e67/wreq](https://github.com/0x676e67/wreq) — Rust native (renamed from rquest)
- [cloudflare/boring](https://github.com/cloudflare/boring) — raw BoringSSL bindings
- [lexiforest/curl-impersonate](https://github.com/lexiforest/curl-impersonate) — active fork (lwthiker dead)
- [Scrapfly: post-quantum TLS bot detection](https://scrapfly.io/blog/posts/post-quantum-tls-bot-detection) — post-quantum state of play

**Flagged risks**: wreq is pre-1.0 and solo-maintained (bus factor 1); uTLS post-quantum alignment is [issue #325](https://github.com/refraction-networking/utls/issues/325); HTTP/3 is not yet in any Rust-native option.

## R8 — HTTP/2 + HTTP/3 fingerprint surface

**Akamai H2 format** ([Shuster/Segal, Black Hat EU 2017](https://blackhat.com/docs/eu-17/materials/eu-17-Shuster-Passive-Fingerprinting-Of-HTTP2-Clients-wp.pdf)):
```
S[...]|WU|P[...]|PS
```
- S = SETTINGS `ID:VALUE` pairs in send order
- WU = connection WINDOW_UPDATE increment
- P = PRIORITY frame list (mostly empty in modern Chrome)
- PS = pseudo-header order `m/a/s/p`

**Current Chrome H2 signature** (stable, recent majors):
- SETTINGS: `HEADER_TABLE_SIZE=65536, ENABLE_PUSH=0, MAX_CONCURRENT_STREAMS=1000, INITIAL_WINDOW_SIZE=6291456, MAX_HEADER_LIST_SIZE=262144`
- WINDOW_UPDATE increment: `15663105` (~15 MiB)
- Pseudo-header order: `:method, :authority, :scheme, :path` (`masp`)
- No H2 PRIORITY frames (Chrome moved to RFC 9218 `priority:` header)

**JA4H** ([FoxIO spec](https://github.com/FoxIO-LLC/ja4/blob/main/technical_details/JA4H.md)): HTTP-layer fingerprint per-request. Structure `JA4H_a_b_c_d`:
- a: method + version + cookie presence + referer presence + header count + lang
- b: sha256 (truncated) of header-name order
- c: sha256 (truncated) of sorted cookie names
- d: sha256 (truncated) of sorted cookie name=value pairs

**HTTP/3/QUIC fingerprinting** (nascent): no ratified "JA4Q" as of Apr 2026. CDNs fingerprint QUIC transport parameters, ALPN, and the TLS ClientHello inside QUIC Initial. Chrome's transport params are distinguishable from quiche/msquic/ngtcp2.

**Rust H2 fidelity problem**: the Rust `h2` crate does not expose SETTINGS order, GREASE values, or pseudo-header order ([hyperium/h2](https://github.com/hyperium/h2)). Matching Chrome's H2 fingerprint requires a forked H2 implementation. `wreq` has its own; using `hyper` + `h2` does not work for this purpose.

**Go equivalent**: same limitation in `golang.org/x/net/http2` ([#32763](https://github.com/golang/go/issues/32763), [#44181](https://github.com/golang/go/issues/44181)); forks like `tls-client` and `azuretls` patch around it.

**Detection vendor usage**:
- [Cloudflare JA4 signals blog](https://blog.cloudflare.com/ja4-signals/) — confirms JA4 + cross-layer correlation
- Akamai: encrypted sensor JS + H2 fingerprint ([scrapfly](https://scrapfly.io/blog/posts/how-to-bypass-akamai-anti-scraping))
- DataDome: H2 consistency used as negative signal ([DataDome comparison](https://datadome.co/comparison/datadome-vs-human-cloudflare-akamai-other-bot-protection-solutions/))

## R9 — Persona diversity in scraping stacks

**Core architectural finding**: a persona is a **frozen bundle** sampled from a joint real-traffic distribution, not a collection of independently-sampled fields.

**Reference implementations**:
- **Camoufox** ([camoufox.com](https://camoufox.com)) — Firefox fork, C++-level fingerprint injection (not JS patches); uses BrowserForge corpus; sample size ~50+ coherent fields per persona
- **BrowserForge** (Apify/Camoufox) — joint-distribution sampler, MIT-licensed, actively maintained
- **curl_cffi** ([docs](https://curl-cffi.readthedocs.io/en/latest/impersonate/fingerprint.html)) — persona as named target string (`chrome145`), HTTP-layer only, no DOM
- **GoLogin / Kameleo / Multilogin** — commercial anti-detect browsers; ~30–53 fingerprint params per profile; closed corpora
- **patchright / rebrowser-patches / undetected-chromedriver** — patch CDP leaks, pair with persona generators rather than replace

**Consistency rules** (from [ScrapFly CreepJS](https://scrapfly.io/blog/posts/browser-fingerprinting-with-creepjs) and [BrightData Camoufox](https://brightdata.com/blog/web-data/web-scraping-with-camoufox)):
- OS ↔ fonts ↔ WebGL renderer are conditional; must be sampled together
- UA ↔ UA-CH full version list must align
- Chrome ≥110 randomises TLS extension order per-handshake; defenders hash with JA3N (sorted extensions) to defeat trivial permutation
- Locale ↔ timezone ↔ IP geo must match
- Hardware_concurrency capped at 8 in Chrome regardless of CPU

**Rotation strategy**: per-session, not per-request. IP + fingerprint + cookie jar flip together at session boundary. Aged personas outperform fresh-per-run.

**Corpus currency**: Chrome ships every ~4 weeks; stale impersonation profiles become detection signals themselves. Refresh pipeline is a first-class requirement.

**Public-info gaps** (flagged for reverse-engineering):
- Exact vendor score weights per mismatch category
- Akamai sensor-data payload schema (obfuscated)
- rebrowser-patches (private/paid)
- BrowserForge corpus refresh cadence (not formally documented)

## R6 — JA4 reference database (deferred)

Research agent lacked web tools; specific JA4 strings per Chrome version were not collected in this pass. Deliverable deferred to the refresh-pipeline workstream (W3A.4) which will capture reference JA4s empirically from `tls.peet.ws` or equivalent as the registry is built. Spec reference for when we collect: [FoxIO JA4](https://github.com/FoxIO-LLC/ja4) (from R7/R8 references).

## Implications for the plan (as of this research round)

- Phase 3 is **not deferred** — it's the owned-fingerprint registry initiative. See `07-fingerprint-registry-design.md`.
- ADR-005 will record: `wreq` primary, `tls-client` fallback, `cloudflare/boring` as deep-control escape hatch.
- Chromium's stock JA4 is accepted as the ground truth for Chromium-emitted traffic; personas declare matching Chrome version.
- Phase 3E (BoringSSL patching) remains deferred, activated only on empirical need.

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
