# Test Strategy — Trusted Automation

## Goals

Each detection layer is testable independently, with a concrete pass/fail signal. No requirement may be marked complete without its acceptance test passing against the corpus in `carbonyl-agent-qa`.

## Test pyramid

```
        ┌─────────────────────────┐
        │  E2E reference sites    │  ← x.com, Turnstile, DataDome demo
        ├─────────────────────────┤
        │  Per-layer probes       │  ← creepjs, bot.sannysoft, custom
        ├─────────────────────────┤
        │  Integration: SDK→site  │  ← carbonyl-agent drives Carbonyl
        ├─────────────────────────┤
        │  Unit: Rust humanizer   │  ← timing distribution statistics
        │  Unit: Rust uinput      │  ← device setup, event encoding
        └─────────────────────────┘
```

## Layer-by-layer acceptance tests

### Layer 1 — Trusted input

**Probe**: minimal static HTML page with:
```html
<input id="i"/>
<script>
  const log = [];
  i.addEventListener('keydown', e => log.push({k: 'keydown', t: e.isTrusted}));
  i.addEventListener('input',   e => log.push({k: 'input',   t: e.isTrusted}));
  i.addEventListener('click',   e => log.push({k: 'click',   t: e.isTrusted}));
</script>
```

**Pass criteria**:
- Agent types `"hello"` via SDK with `input-mode=uinput`
- Every logged event has `t === true`
- Agent clicks at (x,y); click event `t === true`
- Preceding `mousemove` events are present with `t === true`

**Location**: `carbonyl-agent-qa/tests/layer1_trust/`

### Layer 2 — Automation fingerprints

**Probe**: `bot.sannysoft.com` (public reference probe).

**Pass criteria**: green rows for:
- `navigator.webdriver`
- `chrome.runtime` present
- User-Agent clean (no `HeadlessChrome`, no `Carbonyl`)
- Permissions API consistent

**Automation**: scrape the result table; assert count of red rows ≤ documented tolerance.

**Location**: `carbonyl-agent-qa/tests/layer2_automation/`

### Layer 3 — Environment fingerprints

**Probes**: 
- `creepjs.com` (fingerprint-diff score)
- `pixelscan.net` (consistency check)
- Custom page dumping WebGL params, plugins, Notification.permission

**Pass criteria**:
- WebGL `UNMASKED_RENDERER_WEBGL` not containing `"llvmpipe"`, `"Mesa"`, `"Software"`
- `navigator.plugins.length >= 2`
- `Notification.permission === "default"` on fresh profile
- creepjs "trust score" above documented threshold (target: match a typical real-Chrome baseline within ±10%)

**Location**: `carbonyl-agent-qa/tests/layer3_environment/`

### Layer 4 — Behavioral

**Probe**: instrumented page that records every input event with timestamps:
```js
const events = [];
['keydown', 'keyup', 'input', 'mousemove', 'mousedown', 'mouseup', 'click']
  .forEach(k => document.addEventListener(k, e => events.push({
    type: k, t: performance.now(), x: e.clientX, y: e.clientY, key: e.key, trusted: e.isTrusted
  })));
```

**Pass criteria (statistical)**:
- Agent types a 200-character paragraph under `persona=normal`
- Inter-keystroke intervals fit log-logistic (Kolmogorov-Smirnov test, p > 0.05) against a reference human-typed sample
- Bigram timing differs: `"th"` median < `"qz"` median, ratio within human range
- Agent clicks a target 50 times; mouse paths:
  - Overshoot presence in 60–80% of paths
  - Path curvature > 0 (no straight lines)
  - Fitts's-law fit: MT regression coefficient b matches human baseline within ±30%
- Every click preceded by at least one mousemove in the prior 500 ms
- Event sequence order `pointerdown → mousedown → mouseup → click → pointerup` (or Chromium's actual order) preserved on 100% of clicks

**Location**: `carbonyl-agent-qa/tests/layer4_behavioral/`

### Layer 5 — Network fingerprint (Phase 3)

**Probe**: `tls.browserleaks.com` and `tls.peet.ws` JA4 lookup endpoints; HTTP/2 fingerprint at `http2.pro`.

**Pass criteria**: JA4 and HTTP/2 fingerprint strings match current stable Chrome on the same major version, verified against a reference capture.

**Location**: `carbonyl-agent-qa/tests/layer5_network/` (Phase 3)

### Layer 6 — Session / aggregate

**Probes**: 
- Cloudflare Turnstile demo (`challenges.cloudflare.com/turnstile/v0/siteverify` test endpoint)
- DataDome demo page
- (Gated, manual): x.com login flow as per issue #57

**Pass criteria**:
- Cloudflare Turnstile passes passively on ≥90% of 100 fresh sessions
- DataDome demo does not serve CAPTCHA block on ≥90% of 100 fresh sessions
- x.com login flow advances through username → password on ≥80% of attempts using a warmed persona profile

**Location**: `carbonyl-agent-qa/tests/layer6_session/`

## Unit tests

### Rust — uinput emitter (carbonyl)

- Device setup succeeds against a mock `/dev/uinput` (using `tempfile` + FUSE or a test harness)
- Key codes correctly translated: `'a'` → `KEY_A`, `'A'` → `KEY_LEFTSHIFT + KEY_A`, arrow keys, control chars
- `EV_SYN` emitted after each logical event
- Mouse `EV_ABS` coordinates correctly mapped from SGR cell to pixel (given viewport config)
- Device cleanup on drop

### Rust — humanizer (carbonyl-agent)

- Keystroke schedule: generating N=1000 keystrokes, fit to log-logistic passes KS test against known distribution
- Bigram table honored: `"th"` schedule faster than `"qz"` schedule, median difference exceeds threshold
- Mouse path: WindMouse implementation matches reference trajectory for fixed seed
- Bézier + Fitts: `MT` within ±10% of Fitts prediction for given D, W
- Overshoot: fraction of paths with overshoot within configured target (e.g., 60–80%)

### Python — SDK surface (carbonyl-agent)

- `click(x, y)` emits at least one preceding `mousemove` when humanization enabled
- `click(x, y, humanize=False)` emits direct click only (testing/replay mode)
- Persona config loading: YAML → runtime object round-trips
- Profile directory persistence: cookies round-trip across agent sessions

## Integration tests

### Smoke tests (every PR)

- Carbonyl starts with `--input-mode=uinput` without errors; uinput device created and torn down
- Agent types `"hello"` into `<input>` element on a local HTTP test page; value reaches DOM; `isTrusted: true`
- Agent clicks a button on a local page; click handler fires; `isTrusted: true`
- No regression on Layers 1–4 probes vs. main

### Nightly (scheduled)

- Full reference-site corpus (Turnstile, DataDome, creepjs, bot.sannysoft, pixelscan)
- X/Twitter login flow against a dedicated throwaway account (credentials from CI secrets)
- Statistical humanization tests (fresh seed each night; detects timing-distribution drift)

### Regression tracking

- Each test run writes `{test, result, score_if_applicable, timestamp}` to a time-series store
- Dashboard shows per-layer pass rate over time
- Alert when a test that passed yesterday fails today (catches vendor updates)

## Test infrastructure

- **Runner**: `carbonyl-agent-qa` owns the harness; likely Python (pytest) with asyncio for concurrency
- **Fixtures**: local HTTP server for controlled pages; Docker-composed Carbonyl instance for isolation
- **Credentials**: scoped throwaway accounts, secrets injected via CI; never committed
- **Reference captures**: per-layer "golden" fingerprints and timing distributions committed to `carbonyl-agent-qa/fixtures/`; update deliberately
- **CI integration**: `.gitea/workflows/qa-nightly.yml` in `carbonyl-agent-qa`

## Open questions

- Should reference human-typing samples be synthetic (generated from published distributions) or recorded from real users? Decision: synthetic for v1, recorded for v2 when we have an opt-in capture flow.
- How do we handle non-deterministic probe endpoints (e.g., Cloudflare Turnstile) that may change verdict mid-test? Decision: require N successful fresh-session attempts, report pass rate, alert on drop below threshold rather than hard-fail on single miss.
