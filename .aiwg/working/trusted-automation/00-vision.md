# Vision — Carbonyl Trusted Automation

## Problem

Carbonyl today can render modern SPAs in a terminal, but cannot *drive* them reliably. On React-controlled forms like `x.com/i/flow/login`, typed text is rendered into the DOM input but never propagates to React state, because synthetic PTY-derived events fail `event.isTrusted` checks. Even when `isTrusted` passes, modern bot-scoring systems (Akamai, DataDome, PerimeterX, Cloudflare) score sessions against ~50 behavioral and environmental features; failing any of them reduces Carbonyl to a toy for static sites.

Personal automation agents — the primary target consumer of Carbonyl via `carbonyl-agent` — require a browser that looks, behaves, and fingerprints as a human-driven Chrome instance across all layers that modern detection vendors inspect.

## Vision

**Carbonyl becomes the most credible open-source headless browser for personal automation**, surpassing Puppeteer and Playwright on detection-resistance by combining:

1. Real kernel-input-pipeline event provenance (uinput + Ozone evdev wiring)
2. Rigorous fingerprint normalization (WebGL, plugins, Client Hints, `navigator.*`)
3. Research-grounded behavioral humanization (WindMouse/Bézier + Fitts's law + log-logistic keystroke timing)
4. Wire-level indistinguishability from real Chrome (TLS/HTTP2 fingerprint; phase 3)

All delivered as a single layered stack: Chromium patches in `carbonyl`, behavioral layer in `carbonyl-agent`, QA corpus in `carbonyl-agent-qa`, fleet orchestration in `carbonyl-fleet`.

## Success criteria (concrete, per vague-discretion rule)

The initiative succeeds when, on the reference test corpus in `carbonyl-agent-qa`:

- `isTrusted: true` on 100% of keystroke/mouse events emitted by the agent SDK
- X/Twitter login flow (`x.com/i/flow/login`) advances username → password → MFA when driven by `carbonyl-agent` at viewport 1280×800
- Cloudflare Turnstile passive challenge passes (no interactive challenge) on a stable fingerprint profile, measured across 100 fresh sessions with ≥90% pass rate
- DataDome demo page (`datadome.co`) does not serve the CAPTCHA block page on ≥90% of fresh-session visits
- A documented set of fingerprint probes (creepjs, bot.sannysoft.com, pixelscan.net) report no automation/headless tells above the documented tolerance

## Non-goals

- Defeating Akamai Bot Manager on high-protection tier customers (banking, airline) — these run custom scoring models with session-replay detection; out of scope for MVP and likely unachievable without residential IP infrastructure outside Carbonyl's concern
- Residential/mobile proxy infrastructure — this is a procurement and fleet concern, not a Carbonyl/agent concern
- Headed mode — Carbonyl remains terminal-native; we are not adding an X11/Wayland display
- Supporting Windows or macOS — Linux-only is explicit
- CAPTCHA solving — we aim to *not trigger* CAPTCHAs, not to solve them
- Credential theft, session hijacking, or impersonation of users who haven't authorized automation — this toolchain is for operators driving their own accounts

## Stakeholders

| Role | Interest |
|------|----------|
| Personal automation users | Reliable form fill, auth flows, content retrieval against SPAs |
| `carbonyl-agent` maintainers | Clean API surface; humanization as a policy knob, not a foot-gun |
| `carbonyl-fleet` maintainers | Multi-tenant isolation, per-instance device namespacing |
| Carbonyl core maintainers | Minimal Chromium patch burden; upgrade path preserved |
| Security / ethics review | Clear non-goals; no supply-chain risk from new deps |

## Intentionally deferred

- **TLS/HTTP2 fingerprint impersonation** — high-value but requires either invasive BoringSSL patching or a proxy intermediary (uTLS/curl-impersonate). Deferred to Phase 3 with its own research spike; see `02-architecture.md`.
- **Fleet-scale uinput device namespacing** — solvable but only relevant once single-instance automation works. Carbonyl Phase 1 includes the namespacing primitive (`--uinput-device-name`); fleet integration is a separate initiative.

## Out of this doc

- Implementation details → `02-architecture.md`
- Acceptance tests → `04-test-strategy.md`
- What to build first → `05-phase-plan.md`
