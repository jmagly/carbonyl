# Carbonyl Presence Layer Specification

## Purpose

Make agent-driven browsing indistinguishable from human browsing at the behavioral and fingerprint level.

This is not about circumventing security. It is about the reality that agents acting on behalf of users should behave like those users. An agent filling out a form for a person is not categorically different from that person doing it themselves. Bot detection systems that block agents but not the same actions performed by a human on a physical machine are not enforcing a meaningful policy distinction. The presence layer ensures Carbonyl agents are not blocked on those grounds.

Carbonyl does not use the presence layer to impersonate specific individuals, fabricate identity for fraud, or access systems the caller is not authorized to use.

---

## Components

### 1. Timing Humanization

All timing behaviors are off when `preset: instant` is selected. The instant preset is for automated test pipelines where determinism matters more than realism.

#### Keystroke Timing

Inter-key delays follow a Gaussian distribution. The mean and variance differ by preset.

| Preset | Mean Delay | Variance | Description |
|---|---|---|---|
| `fast` | 30-80ms | Low | Professional typist — fast and consistent |
| `natural` | 80-200ms | Medium | Average user — noticeable pause between keys |
| `deliberate` | 200-500ms | High | Careful or unfamiliar user |
| `instant` | 0ms | None | No humanization. Testing only. |

Additional keystroke behaviors:

- Variance increases at word boundaries — a brief pause between words is injected proportional to word length
- Shift key pre-hold: uppercase letters include a slight delay between Shift keydown and the character key, simulating natural finger coordination
- Backspace + retype (configurable error rate, default 0%): occasionally a character is typed, immediately deleted, and retyped, simulating a correction. Enabled via `error_rate` config.

#### Mouse Movement

Mouse trajectories use cubic Bezier curves rather than linear interpolation. This approximates the natural acceleration and deceleration of hand movement.

- Speed profile: accelerate from origin, reach peak speed at midpoint, decelerate near target (Fitts's Law approximation — larger targets are approached faster)
- Overshoot and correction: approximately 10% of movements overshoot the target by a few pixels and immediately correct. Rate is configurable.
- Micro-jitter: ±1-2px random offset is applied to trajectory control points, simulating hand tremor. Not perceptible visually but present in CDP mouse event coordinates.
- Movement duration is proportional to distance traveled

#### Click Timing

- `mousedown` to `mouseup` duration: 80-150ms (natural click hold duration)
- Double-click gap between the two clicks: 100-200ms
- Right-click hold: slightly longer than left-click on average, consistent with context-menu intent

#### Scroll Behavior

- Scroll events are not instantaneous `window.scrollTo` calls — they are emitted as a series of smaller delta events with a deceleration curve (fast start, slow stop, simulating momentum)
- Scroll amount per gesture is variable — not always exactly one viewport height
- Occasional mid-scroll pause: simulates a user stopping to read before continuing

#### Navigation Timing

- Dwell time between page loads: 1-5 seconds by default (configurable). Agents do not navigate immediately after a page loads — a brief pause simulates reading or decision time.
- Consecutive navigations with zero dwell time are a well-known bot signal. The presence layer enforces a minimum gap between navigation events.

#### Preset Summary

| Preset | Keystroke | Mouse Move | Dwell Time | Description |
|---|---|---|---|---|
| `fast` | 30-80ms | 200-400ms | 0.5-1.5s | Efficient operator |
| `natural` | 80-200ms | 400-800ms | 1-5s | Average user |
| `deliberate` | 200-500ms | 800-1500ms | 3-10s | Careful or new user |
| `instant` | 0ms | 0ms | 0ms | No humanization. Testing only. |

---

### 2. Identity Profiles

An identity profile is a coherent set of browser fingerprint signals that jointly define a plausible user environment. The signals must be internally consistent — an incoherent combination (e.g., a Firefox UA paired with Chrome-specific APIs) is more detectable than no spoofing at all.

#### Profile Properties

| Property | Description |
|---|---|
| `user_agent` | Full UA string. Must be consistent with all other signals. |
| `platform` | `navigator.platform` value. Must match OS implied by UA. |
| `vendor` | `navigator.vendor` value. |
| `viewport` | Browser viewport dimensions (width x height). |
| `screen` | Physical screen (width x height x colorDepth x devicePixelRatio). Screen must be >= viewport. |
| `timezone` | IANA timezone name, e.g. `America/New_York`. |
| `locale` | Language and region code, e.g. `en-US`. |
| `webgl_vendor` | WebGL `UNMASKED_VENDOR_WEBGL` string. |
| `webgl_renderer` | WebGL `UNMASKED_RENDERER_WEBGL` string. Must be a plausible GPU for the platform. |
| `canvas_noise` | Integer seed for deterministic canvas noise injection. Consistent per identity across sessions. |
| `fonts` | Available font list. Must be appropriate for the declared platform/OS. |
| `hardware_concurrency` | `navigator.hardwareConcurrency` — CPU core count. Must be plausible (2-32). |
| `device_memory` | `navigator.deviceMemory` — RAM in GB. Must be plausible (1-64). |
| `do_not_track` | `navigator.doNotTrack` — `null`, `"1"`, or `"0"`. |

#### Coherence Rules

The following constraints are enforced at profile creation. Profiles that violate these rules are rejected.

| Signal Combination | Requirement |
|---|---|
| Firefox UA | Chrome-specific APIs must not be present. WebGL strings must match Firefox-reported values for the declared platform. |
| macOS platform | Font list must contain macOS system fonts. WebGL renderer must be an Apple GPU string. |
| Mobile viewport (width < 768) | Touch events must be enabled. UA must be a mobile UA. |
| Timezone and locale | Timezone must be plausible for the declared locale region (e.g., `en-US` with `America/*` timezone). Exact match not required — `en-US` with `Europe/London` is allowed for VPN simulation. |
| Screen and viewport | `screen.width >= viewport.width` and `screen.height >= viewport.height`. |

#### Profile Management

Profiles can be managed by name:

- **Create**: Generate a coherent profile from a minimal descriptor such as `"desktop-us"` or `"mobile-eu"`. All fields are auto-populated with internally consistent values for the described environment.
- **Store**: Named profiles persist across sessions and are stored in the Carbonyl configuration directory.
- **Reuse**: A session bound to a named profile will use the same profile after hibernation and restore. Identity continuity is preserved.
- **Rotate**: Generate a new coherent profile on demand for fresh-start scenarios (e.g., creating a new account). The rotated profile replaces the prior one under the same name unless a new name is specified.

---

### 3. Fingerprint Injection

All overrides are applied via Chrome DevTools Protocol (CDP) before any page loads. Injection happens on the browser context, not per-page, so it is consistent across all tabs and navigations within a session.

#### CDP-Level Overrides

| Target | CDP Method |
|---|---|
| User agent, platform, accept-language | `Network.setUserAgentOverride(userAgent, platform, acceptLanguage)` |
| Timezone | `Emulation.setTimezoneOverride(timezoneId)` |
| Locale | `Emulation.setLocaleOverride(locale)` |
| Geolocation (optional) | `Emulation.setGeolocationOverride(latitude, longitude, accuracy)` |
| Touch emulation (mobile profiles) | `Emulation.setTouchEmulationEnabled(enabled, maxTouchPoints)` |

#### Script-Level Overrides

The following are injected via `Page.addScriptToEvaluateOnNewDocument()`, which runs before any page script:

```javascript
// WebGL vendor and renderer
const getParameter = WebGLRenderingContext.prototype.getParameter;
WebGLRenderingContext.prototype.getParameter = function(parameter) {
  if (parameter === 37445) return INJECTED_WEBGL_VENDOR;    // UNMASKED_VENDOR_WEBGL
  if (parameter === 37446) return INJECTED_WEBGL_RENDERER;  // UNMASKED_RENDERER_WEBGL
  return getParameter.call(this, parameter);
};

// Canvas fingerprint noise (deterministic per identity seed)
const toDataURL = HTMLCanvasElement.prototype.toDataURL;
HTMLCanvasElement.prototype.toDataURL = function(type) {
  const dataURL = toDataURL.call(this, type);
  return injectCanvasNoise(dataURL, INJECTED_CANVAS_SEED);
};

// Hardware concurrency
Object.defineProperty(navigator, 'hardwareConcurrency', {
  get: () => INJECTED_HARDWARE_CONCURRENCY
});

// Device memory
Object.defineProperty(navigator, 'deviceMemory', {
  get: () => INJECTED_DEVICE_MEMORY
});
```

All `INJECTED_*` constants are populated from the active identity profile before the script is registered.

---

### 4. Existing Measures (from browser.py — preserved)

The following flags are already present in the Chromium launch configuration and must not be removed:

| Flag | Purpose |
|---|---|
| `--disable-blink-features=AutomationControlled` | Suppresses `navigator.webdriver = true` — the most commonly checked bot signal |
| `--disable-http2` | Avoids the Chrome-specific HTTP/2 SETTINGS frame fingerprint that identifies headless Chromium |
| `--password-store=basic --use-mock-keychain` | Suppresses OS keychain integration dialogs that would block headless execution |
| `--no-first-run --no-default-browser-check --disable-sync` | Prevents first-run UI flows and background sync activity that produce anomalous network patterns |

These flags apply to all sessions regardless of presence configuration.

---

## Configuration

Presence settings are declared in `carbonyl.yaml` under the `presence` key.

```yaml
presence:
  timing:
    preset: natural          # fast | natural | deliberate | instant
    keystroke_mean_ms: 120   # Override the preset's default mean. Optional.
    mouse_speed: 1.0         # Multiplier applied to all mouse movement durations.
                             # 0.5 = half speed. 2.0 = double speed.
    error_rate: 0.02         # Probability of a typo+backspace per keystroke. Default: 0.
  identity:
    profile: residential-us  # Named profile to load. Or inline config (see below).
    rotate_every: 0          # Sessions before rotating identity. 0 = never rotate.
  injection:
    webgl: true              # Inject WebGL vendor/renderer overrides.
    canvas_noise: true       # Inject deterministic canvas noise.
    font_enumeration: true   # Override font enumeration APIs.
    hardware: true           # Override hardwareConcurrency and deviceMemory.
```

Inline identity config (alternative to named profile):

```yaml
presence:
  identity:
    profile:
      user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ..."
      platform: "MacIntel"
      viewport:
        width: 1440
        height: 900
      timezone: "America/Chicago"
      locale: "en-US"
      webgl_vendor: "Apple Inc."
      webgl_renderer: "Apple M2"
      hardware_concurrency: 8
      device_memory: 16
```

---

## Metrics and Validation

### Timing Distribution Testing

Keystroke and mouse timing distributions should be validated against real human samples using the Kolmogorov-Smirnov test. The null hypothesis is that the agent's timing distribution is drawn from the same distribution as human samples. Tests should be run:

- On each preset during development
- After any change to timing parameters
- As part of the CI pipeline for presence-affecting changes

Target: KS test p-value > 0.05 for `natural` preset against a representative human sample.

### Fingerprint Coherence Validation

Profile coherence rules (see above) are enforced at profile creation time. The server will reject profile creation requests that produce incoherent signal combinations. Validation runs as a synchronous check before any profile is stored or bound to a session.

### Bot Detection Score Tracking

Carbonyl maintains a benchmark suite that runs sessions against known bot detection services and records detection scores over time:

| Service | What It Measures |
|---|---|
| CreepJS | Comprehensive fingerprint consistency checks |
| FingerprintJS Pro | Commercial-grade browser fingerprinting |
| Cloudflare Bot Management (challenge page) | Behavioral + fingerprint heuristics |
| Akamai Bot Manager (test endpoint) | Network behavior and TLS fingerprint |

Scores are recorded per-commit in CI. Regressions (rising detection scores) block release. Improvements are noted in the changelog.

The benchmark suite is in `scripts/presence-benchmark/` and can be run locally with `pnpm run benchmark:presence`.
