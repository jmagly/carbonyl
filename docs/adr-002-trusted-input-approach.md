# ADR-002: Trusted Input Approach — `/dev/uinput` + Chromium Headless Ozone Evdev

**Date:** 2026-04-18
**Status:** DRAFT (gate: Phase 0 validation spike)
**Deciders:** Carbonyl core team
**Related:** Epic `#58`, issue `#57` (W1.1), issue `#59` (W1.2)

---

## Status

DRAFT — awaiting Phase 0 validation spike result. Finalized (APPROVED or REJECTED) when the spike reports back on whether uinput events reach Blink with `isTrusted: true`.

---

## Context

Carbonyl drives a headless Chromium by writing synthetic input events to the browser's C++ entry points (`OnKeyPressInput`, `OnMouseUpInput`, etc. in `chromium/src/headless/lib/browser/headless_browser_impl.cc`). These events construct `NativeWebKeyboardEvent` and `blink::WebMouseEvent` directly and call `RenderWidgetHost::ForwardKeyboardEvent` / `ForwardMouseEvent`. The events reach Blink, but `event.isTrusted` is `false` because Blink sets that flag based on whether the event came up through a real OS input pipeline.

Modern React-controlled forms (e.g. `x.com/i/flow/login`) refuse to propagate input state when `isTrusted` is `false`. Typing text renders into the DOM input element but never updates React state; the field clears on the next render cycle. This blocks scripted interaction with most modern SPAs.

Issue #57 proposed emitting events via `/dev/uinput` — a Linux kernel API for creating virtual input devices. The theory: events emitted through uinput would flow through the normal kernel input subsystem and reach Chromium through whatever evdev reader it has, producing `isTrusted: true` events indistinguishable from a physical USB keyboard/mouse.

Research (`.aiwg/working/trusted-automation/06-research-index.md` R1) confirmed the Carbonyl Chromium tree has the full `ui/events/ozone/evdev/` subsystem present but **not compiled into the headless platform**. Chrome OS uses this reader; headless does not.

---

## Options Evaluated

### Option A — uinput + wire evdev into headless Ozone (this ADR's proposal)

Patch Chromium's headless Ozone platform to include `//ui/events/ozone:evdev` and replace `StubInputController` with `InputControllerEvdev`. Rust side emits events via `/dev/uinput`; kernel delivers them to `/dev/input/eventN`; the newly-wired evdev reader in Chromium consumes them and dispatches real `ui::Event` objects into Blink.

**Pros:**
- Events originate from a real kernel input device; `isTrusted: true` is structural, not flag-manipulable
- Timing grain inherits real-kernel properties (no need to simulate human timing at the browser-injection boundary)
- Indistinguishable from a physical keyboard/mouse to any Blink-side fingerprinting
- Uses existing, Chrome OS-battle-tested Chromium code (`EventFactoryEvdev`, `KeyboardEvdev`, `DeviceManager`) — not greenfield
- Integration surface is ~100 LOC of Chromium BUILD.gn + initialization changes; Rust side is ~120 LOC of libc calls in a new `src/input/uinput.rs`

**Cons:**
- Requires a Chromium patch with nontrivial thread-coordination concerns (evdev's own event thread vs Carbonyl's FFI callback path)
- Linux-only (acceptable; Carbonyl is Linux-only anyway)
- Operator permission friction: `/dev/uinput` needs `input` group or a udev rule
- Fails fast if Chromium's headless Ozone doesn't actually consume the evdev events we route to it — exactly what the Phase 0 spike validates

### Option B — CDP `Input.dispatchKeyEvent` path

Use Chrome DevTools Protocol's `Input.dispatchKeyEvent` / `Input.dispatchMouseEvent`. These are privileged-process calls within Chromium and produce `isTrusted: true`.

**Pros:**
- Works today across all Chromium versions
- No Chromium patch needed
- Cross-platform (moot for us, but a fact)
- Playwright/Puppeteer battle-tested

**Cons:**
- Event provenance is "browser privileged process," not "kernel input pipeline" — distinguishable by advanced bot detection via side-channels (absence of `InputDevice` correlates, timing patterns, absence of concurrent evdev activity on the host)
- Requires running a CDP endpoint inside Carbonyl, exposing a debugger port, and plumbing CDP into Carbonyl's input loop
- `isTrusted` passes but the broader "real human at a real keyboard" signal doesn't — which is the entire point of the exercise

Option B is the Playwright/Puppeteer equivalent. It solves Layer 1 (`isTrusted`) but not the stronger provenance signal that a persona-coherent automation stack wants.

### Option C — Do nothing (synthetic injection, current state)

Retained as the `--input-mode=synthetic` fallback. Not viable as the default for agent use.

---

## Decision (tentative — pending Phase 0 result)

Proceed with **Option A**. Rust-side emitter via `/dev/uinput` + Chromium patch wiring `EventFactoryEvdev` into headless Ozone. Retain Option C's synthetic path as a `--input-mode=synthetic` fallback for debugging and for environments where `/dev/uinput` is unavailable.

Option B stays available as a further fallback if Option A proves impractical, but is not pursued as the primary path because it doesn't deliver the bot-detection-avoidance value that motivated the initiative.

---

## Phase 0 validation spike (gate to this ADR's finalization)

Before committing to the Chromium patch work in #57, run this experiment:

1. Apply a minimal proof-of-concept patch to a local Carbonyl build:
   - Add `//ui/events/ozone:evdev` to `chromium/src/ui/ozone/platform/headless/BUILD.gn` deps
   - In `OzonePlatformHeadlessImpl::InitializeUI()` (`ozone_platform_headless.cc:122-138`), replace `StubInputController` with an `InputControllerEvdev` instance backed by a `DeviceManager` scanning `/dev/input`
2. Load `carbonyl-agent-qa/tests/spike/istrusted_logger.html` (the test page with an `isTrusted` listener) in the patched Carbonyl
3. From a Python process running alongside Carbonyl, emit a keystroke to `/dev/uinput` via the `python-uinput` library
4. Observe page output

**Outcomes:**
- **`isTrusted: true`** on the logger — decision **APPROVED**. Proceed with W1.1 + W1.2 at full scope. Update this ADR's Status to APPROVED.
- **`isTrusted: false`** or event doesn't arrive — decision **needs revision**. Possible causes:
  - `DeviceManager` didn't pick up the virtual device (timing / initialization order)
  - Headless Ozone dispatches the event but it's still marked synthetic at the Blink boundary
  - Missing a `PlatformEventSource` that actually routes evdev-sourced events into the headless event loop
  - In each case, diagnose and either re-run or fall back to Option B. Update this ADR accordingly.

Spike procedure lives in `roctinam/carbonyl-agent-qa/tests/spike/README.md`.

---

## Consequences

### Positive

- Input provenance problem solved at the kernel boundary; no ongoing flag-maintenance work per Chromium release
- `isTrusted` check (Layer 1) eliminated from the bot-detection surface
- Sets up the behavioral humanization story (Phase 2B): if timing grain comes from real kernel I/O, we inherit human-ish timing for free at the event-dispatch boundary (humanization just has to generate sensible inter-keystroke intervals — no microsecond-level jitter required in userspace)

### Negative

- Carrying a Chromium patch that touches Ozone platform initialization. Moderate rebase tax per major Chromium upgrade; mitigated because we're wiring existing Chromium code rather than adding new code
- `/dev/uinput` permission story complicates container deployments. Documented workaround: `--device=/dev/uinput --group-add input` on `docker run`
- One more thread of concern in the Chromium tree (`EventThreadEvdev` interaction with Carbonyl's existing FFI input path). Hybrid mode (`--input-mode=synthetic|uinput`) keeps both paths available during transition

### Neutral

- `/dev/uinput` is Linux-only. Carbonyl is Linux-only. No regression

---

## Follow-ups

- Write ADR-006 on Chromium-version rebase strategy for this patch (tracked against future upgrades)
- File udev-rule template in `docs/uinput-setup.md` for operator convenience
- Measure end-to-end latency (PTY keystroke → Blink event) before and after; compare with Option B (CDP) as a reference

---

## References

- `.aiwg/working/trusted-automation/07-fingerprint-registry-design.md` — owned fingerprint registry, which consumes trusted input
- `.aiwg/working/trusted-automation/06-research-index.md` R1 — headless Ozone evdev path research
- `.aiwg/working/trusted-automation/02-architecture.md` §3.1 — trusted input sequence diagram
- Issue #57 — trusted input via `/dev/uinput` (original)
- Issue #59 — Rust uinput emitter + CLI flags (companion)
- Epic #58 — Trusted Automation Initiative umbrella
