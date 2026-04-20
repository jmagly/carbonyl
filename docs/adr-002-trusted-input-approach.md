# ADR-002: Trusted Input Approach — Xorg-in-Container + Carbonyl `ozone_platform=x11`

**Date:** 2026-04-19 (rev 2; rev 1 was headless-Ozone evdev wiring)
**Status:** DRAFT (gate: Phase 0 container-build spike)
**Deciders:** Carbonyl core team
**Related:** Epic `#58`, issue `#57` (rescoped), ADR-003 (humanization), `09-ci-plan.md` (container shape)

---

## Status

DRAFT — superseding rev 1. Rev 1 proposed patching Chromium's headless Ozone platform to read `/dev/input` via `EventFactoryEvdev`. The sanity check on 2026-04-19 validated that `uinput → kernel → Xorg → focused browser = isTrusted=true` end-to-end when a real X server sits between the kernel and Chromium. That observation + the deployment requirement that containers host both (a) Carbonyl's text render **and** (b) a capturable graphical screen led to a simpler architecture: run Carbonyl with `ozone_platform=x11` under a containerized Xorg. No Chromium patch needed for input; `isTrusted: true` comes for free through the X server exactly as it does on any normal desktop Chrome.

Finalized when the Phase 0 spike confirms the `ozone_platform=x11` build of Carbonyl retains its terminal rendering alongside the X framebuffer output.

---

## Context

Earlier drafts of this ADR framed the choice as **uinput + Chromium patch (headless Ozone)** vs **CDP `Input.dispatchKeyEvent`**. Two things shifted that framing:

1. **Empirical sanity check (2026-04-19 on grissom)** — `python-uinput` + the isTrusted logger page confirmed that uinput events reach a real browser with `isTrusted: true`. The X server at the kernel→browser boundary is what makes the provenance work. Chromium didn't need patching; the stock distribution already consumes evdev events when there's an X server feeding them in.

2. **Container deployment requirement** — production automation runs in Docker. Operators need both the text render from Carbonyl (agents consume it) *and* a visual framebuffer capture (observability, screenshots, video streaming). That argues for an X server inside the container anyway — making the first point a free lunch: with Xorg already in the container, we don't need to teach headless Chromium to read evdev; we just use Chromium's `x11` Ozone platform.

The combination collapses the Chromium-patch side of the problem. Trusted input is now the normal desktop Chrome story, just inside a container.

---

## Options Evaluated (revised)

### Option A — Xorg-in-container + `ozone_platform=x11` (this ADR's proposal)

Build Carbonyl with `ozone_platform=x11` instead of `headless`. Container bundles Xorg (driver = `dummy` for CPU-only, or `modesetting`/vendor for GPU operator opt-in). Container entrypoint starts Xorg on `:99`, exports `DISPLAY=:99`, launches Carbonyl. Agent SDK emits keystrokes into the container via uinput (device passed through with `--device=/dev/uinput`). Xorg reads `/dev/input/eventN`, dispatches into Chromium as normal X11 events with kernel-backed provenance.

**Pros:**
- No Chromium patch for input. Zero rebase tax per major Chrome upgrade.
- Unlocks visual capture as a side effect: `scrot`/`ffmpeg`/`x11vnc` against `DISPLAY=:99` produces real browser screenshots and streams, alongside Carbonyl's terminal rendering.
- Operator gets CPU/GPU choice via env var (`CARBONYL_GPU_MODE=auto|cpu|gpu`) and matching `/dev/dri` passthrough on `docker run`.
- Same pattern Chrome OS and every normal Linux desktop already uses — not a novel code path.
- Fingerprint provenance is real-kernel, same property we wanted from rev 1.

**Cons:**
- Carbonyl must build with `ozone_platform=x11`. Its existing patches (0001–0024) target `headless`; some may need rework. **This is what the Phase 0 spike now validates** — whether the rendering bridge patches still work when Chromium thinks it has an X display.
- Slightly larger container image (Xorg + video driver + tooling — on the order of tens of MB).
- One more process (Xorg) per container, which is mostly idle but uses some RAM/fds.

### Option B — Xvfb-in-container (rejected)

Looks tempting but **Xvfb doesn't read `/dev/input`** — it only accepts input via the X11 protocol (XTEST). That means we'd need `xdotool` for input, which is fine for `isTrusted` (XTEST-injected events are marked trusted by the X server) but loses the kernel-pipeline provenance we want. Rejected.

### Option C — `ozone_platform=headless` + Chromium evdev patch (rev 1 of this ADR)

Still viable as a deployment pattern for pure-text-no-screenshot environments. Parked — not pursued unless a future deployment has a hard constraint against running Xorg.

### Option D — CDP `Input.dispatchKeyEvent`

Works but doesn't deliver kernel-pipeline provenance; same objection as rev 1. Kept as a documented fallback if Option A's spike reveals blocking issues.

### Option E — Do nothing (synthetic)

Current state. Not viable as agent default.

---

## Decision (tentative — pending Phase 0 spike result)

Proceed with **Option A**. Build Carbonyl with `ozone_platform=x11`, package in a container bundling Xorg + `dummy`/`modesetting` drivers + uinput passthrough, let agent SDK emit input via uinput from outside the container process. Option C retained as a documented fallback for non-container deployments.

Rev 1's Chromium evdev-wiring patch work is **shelved** unless Option A's spike reveals that Carbonyl's existing patch set is incompatible with `ozone_platform=x11`.

---

## Phase 0 spike — what now gets validated

Before committing to Option A, validate:

1. **Can Carbonyl build with `ozone_platform=x11`?** Change `gn.sh args` to set `ozone_platform="x11"` + `ozone_platform_x11=true` and rebuild. Patches 0001–0024 must either apply cleanly or be flagged for revision.
2. **Does Carbonyl's terminal render still work under `ozone_platform=x11`?** Run the existing text-mode fixtures and compare to a headless-ozone baseline. Rendering bridge patches (0003, 0006, 0009–0014) are the risk surface.
3. **Does `uinput → Xorg → Chromium` deliver `isTrusted: true` inside a container?** Build the `carbonyl-agent-qa-runner` container with Xorg+dummy, load the isTrusted logger, run the Python uinput driver we already validated on the host. Expected PASS given the 2026-04-19 host-side result.
4. **Capture the X framebuffer.** Confirm `scrot` / `ffmpeg -f x11grab` produce a valid image/stream from `DISPLAY=:99` while Carbonyl is running.

### Outcomes

- **All four PASS**: ADR-002 → APPROVED. Carbonyl builds and ships with Option A.
- **Build fails (patches incompatible with x11 Ozone)**: revise specific patches OR fall back to Option C (headless Ozone + evdev patch, rev 1's path).
- **Text render regresses under x11**: same — revise patches or fall back.
- **isTrusted check fails inside container**: investigate (unusual given host sanity pass); likely points to container-specific X setup issue, not architecture.

Spike procedure updated in `roctinam/carbonyl-agent-qa/tests/spike/README.md`.

---

## Consequences

### Positive

- No Chromium patch for input; one fewer permanent maintenance burden for the Carbonyl patch set
- Visual capture (screenshots, streams) is a free side effect — addresses observability requirements without new code
- GPU opt-in for operators with capable hosts; CPU default works everywhere
- Container deployment is the standard one (Xorg + client app) — familiar ops story
- Sanity check evidence from 2026-04-19 strongly favors this path

### Negative

- Container is slightly heavier (Xorg + video driver tooling)
- Carbonyl's `ozone_platform=headless` build becomes secondary — the team maintains two Ozone targets (x11 primary, headless for special cases)
- If Carbonyl's existing patches break under `x11`, we incur patch-triage cost up front

### Neutral

- Input emission moves from "Rust crate inside Carbonyl" (rev 1's `src/input/uinput.rs`) to "Python or Rust module inside `carbonyl-agent`" — the agent SDK owns input now, which is a cleaner boundary anyway

---

## Follow-ups

- **Issue #57** rescopes from "wire evdev into headless Ozone" → "build x11 Ozone + package Xorg container"
- **Issue #59** (Rust uinput emitter in Carbonyl) — close; work moves to a new `carbonyl-agent` issue
- New issue in `carbonyl-agent`: Python uinput driver module + container entrypoint script for `DISPLAY` + `CARBONYL_GPU_MODE` handling
- New issue in `carbonyl`: build variant `ozone_platform=x11` — patch-compatibility audit + CI build both Ozone variants

---

## References

- Sanity-check result: 2026-04-19, on grissom — uinput→Xorg→browser delivered `isTrusted: true` via `python-uinput`
- `.aiwg/working/trusted-automation/02-architecture.md` §3.1 — updated sequence diagram
- `.aiwg/working/trusted-automation/09-ci-plan.md` — container shape + CPU/GPU operator choice
- Rev 1 of this ADR (now superseded): was at `docs/adr-002-trusted-input-approach.md` commit `43769c2`
- `chromium/src/ui/ozone/platform/x11/` — target Ozone backend for Option A
- `chromium/src/ui/ozone/platform/headless/` — Option C's target (parked unless spike drives us back)
