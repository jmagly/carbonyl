# Quality Review Gate: Operator Zoom and Extensions Center

**Date:** 2026-09-03
**Scope:** Focused re-review of the remediated issue-planner corpus and four draft issue bodies; not a full project IOC evaluation.
**Decision:** **READY**
**Recommendation:** The four draft bodies are ready for policy composition, human approval, and tracker filing. This decision does not waive the accepted-ADR and popup/options-hardening prerequisites for the production extensions center.

## Gate result

| Prior condition | Result | Concise evidence |
|---|---|---|
| G1 — zoom persistence and acknowledgment | Pass | The synthesis, UC-OZ-001, architecture, R-OZ-03, test strategy, and zoom issue now require durable Chromium-compatible per-host settings for persistent profiles, no writes for ephemeral/off-the-record contexts, reset removal, and a preference-write barrier distinct from the existing cookie/storage acknowledgment. Crash-before/after, process-exit, host/profile isolation, corrupt-value, and same-profile reload behavior are test-pinned. |
| G2 — WebUI go/no-go | Pass | The spike issue requires an accepted ADR and executable M150 proof for exact origin/factory registration, process lock before binding, typed Mojo, bundled resources/CSP, browser-side reauthorization, active-page ownership, DTOs, teardown, and dependency/size/startup impact. Failure blocks production WebUI and returns the native Views fallback for separate architecture approval. |
| G3 — popup/options hardening | Pass | A separate defect/security issue owns trusted identity, pre-commit navigation enforcement, new-window/download/dialog denial, bounded sizing, dismissal/focus restoration, crash/disable behavior, and teardown. The extensions center depends on its completion before exposing action/options. R-EX-07 and hostile regression coverage trace this work. |
| G4 — isolated Ubuntu/Titan/Wayland safety | Pass | The test strategy defines a fail-before-browser launcher requiring `CARBONYL_DISPOSABLE_BROWSER_QA=1`, approved Ubuntu 26.04 or 24.04 guest identity, guest-owned Xorg on `DISPLAY=:99`, no Wayland or inherited Titan endpoints, recorded artifact/environment provenance, and negative tests for every guard. Both Ubuntu targets and US plus non-US XKB coverage are mandatory. |
| G5 — deterministic acceptance | Pass | Zoom targeting is explicitly the primary page across page/address/center/popup/options focus; unmodified characters remain focused-surface input. Reset, min/max, focus, accessibility, 200%/400% fixture bounds, pointer mapping, terminal progress, extension ordering/scroll/focus, policy modes, restart state, and no-live-mutation outcomes have objective assertions rather than screenshot-only observation. |
| G6 — provenance and traceability | Pass | `research-vendor-docs.md` is present; the synthesis distinguishes the requested WebUI choice from the research preference for native Views; the plan links exact bodies and maps each issue to requirements, risks, and evidence. Baseline-sensitive research remains pinned to `c0693e12`. |

## Draft issue readiness

| Draft | Decision | Filing/implementation gate |
|---|---|---|
| A — durable operator page zoom | Ready | Independent. Acceptance covers accelerator variants, geometry invariants, main-page targeting, accessible feedback, preference durability, deterministic UI behavior, documentation, and isolated Xorg QA. |
| B — secure extension WebUI spike | Ready | Must conclude with an accepted go/no-go ADR. A no-go prevents the production WebUI issue from starting. |
| C — popup/options hardening | Ready | Independent defect/security work and a prerequisite for action/options exposure from the center. |
| D — extensions center | Ready to file | Implementation must wait for an accepted Draft B ADR and completion of Draft C. It retains restart-only policy and excludes onboarding, remote/store/update, native messaging, optional grants, profile scanning, and broad WebExtensions API scope. |

## Security and risk disposition

All identified Critical risks have explicit blocking controls and evidence:

- **R-EX-01:** exact WebUI factory/origin/process lock and negative binding tests;
- **R-EX-03:** browser-side mode, ID, operation, activation, profile, and ownership reauthorization;
- **R-EX-05:** Load Unpacked, filesystem/profile discovery, and silent source authorization remain excluded;
- **R-QA-01:** fail-closed guest preflight exits before browser launch on any unsafe signal.

R-EX-07 now covers popup/options identity and escape paths, and must close before Draft D exposes those operations. No unmitigated Critical risk remains in the planning baseline.

## Ready-to-file conditions satisfied

The final corpus now makes the following unambiguous:

1. persistent profiles use durable per-host zoom; ephemeral/off-the-record contexts are session-only;
2. preference-write completion is separate from storage/cookie shutdown acknowledgment;
3. reserved zoom shortcuts always target the primary page across all operator focus contexts;
4. the privileged WebUI proceeds only after an accepted M150 security/build ADR;
5. popup/options security hardening has a named owner and blocks relevant center exposure;
6. browser/display/GPU/input acceptance runs only through negative-tested Ubuntu guest/Xorg safeguards; and
7. each filed issue carries testable acceptance, non-goals, dependencies, and requirements/risk/test traceability.

**Final disposition: READY for approval and filing.**
