# Architecture Gate Review: Operator Zoom and Extensions Center

**Review date:** 2026-09-03

**Gate type:** Focused issue-planner corpus review; not a project or IOC gate

**Baseline:** `origin/main` at `c0693e12a78703aee89f5c0983b2c86e697604cb`

**Final decision:** **READY**

## Decision

The remediated planning corpus and four draft issue bodies are ready for the
mandatory human filing-approval gate. The earlier architecture, requirements,
traceability, duplicate-disposition, and dependency gaps are closed at planning
depth.

READY does not authorize tracker writes. The plan remains correctly marked
`Awaiting human approval`; the scope assumptions and four exact bodies must be
approved before policy composition and filing.

## Evidence reviewed

- Research:
  `research-best-practices.md`, `research-current-state.md`,
  `research-vendor-docs.md`, and `research-synthesis.md`
- Requirements:
  `@.aiwg/requirements/UC-operator-zoom-extension-center.md`
- Architecture:
  `@.aiwg/architecture/sketch-operator-zoom-extension-center.md`
- Filing preview:
  `@.aiwg/working/issue-planner/issue-plan-operator-zoom-extension-center.md`
- Exact draft bodies:
  `operator-page-zoom.md`, `secure-extension-webui-spike.md`,
  `extension-surface-hardening.md`, and `extensions-center-webui.md`

The referenced zoom, extension, risk, security, and test identifiers exist and
are consistently routed from the plan into the draft bodies.

## Prior gate findings

| Finding | Remediation evidence | Result |
|---|---|---|
| G-01 Scope and architecture unresolved | The synthesis now defines “web extensions interface” as a browser-owned HTML/CSS/JS management UI, explicitly excludes broad WebExtensions APIs, explains why the request overrides the native-first research preference, and retains native Views only as a no-go fallback requiring a new approval. Durable per-host zoom is also selected explicitly. | CLOSED |
| G-02 Manager lacked active-page context | The architecture defines an operator-owned lifetime-safe bridge whose primary page URL drives action/access state. Draft B must prove navigation, crash, close, callback invalidation, and `BrowserContext` teardown behavior; Draft D must consume the accepted bridge. | CLOSED |
| G-03 Existing DTO could not meet UC-OZ-002 | UC-OZ-002 and the architecture now require an immutable browser-owned DTO distinguishing requested/accepted APIs and declared/effective host access. Draft B prototypes it; Draft D implements it with identity bounds, sanitization, deterministic ordering, stable errors, and log/telemetry redaction. | CLOSED |
| G-04 Popup/options hardening unowned | Draft C is a focused bug/security follow-up to #290/#306 with identity, pre-commit navigation, new-window/download/dialog denial, sizing, dismissal, focus restoration, crash/disable, shortcut, and teardown acceptance. Draft D depends on its completion before exposing action/options. | CLOSED |
| G-05 Zoom contract incomplete | UC-OZ-001, the architecture, and Draft A now define Chromium-compatible host keys, default/reset behavior, ephemeral no-write, corrupt-value fallback, a `ZoomLevelDelegate`/profile-pref bridge, acknowledged write behavior, a direct `//components/zoom` dependency, and shared shortcut routing across all operator surfaces. | CLOSED |
| G-06 Research source/dissent unresolved | `research-vendor-docs.md` now exists. The synthesis includes an explicit architecture decision table and records why WebUI is conditionally selected despite the native-first recommendation. | CLOSED |
| G-07 Preview not filing-ready | The preview links four complete bodies containing summaries, context, testable criteria, non-goals, dependencies, artifact/risk/test traceability, and research bases. #156 is Parent/Related rather than a blocking dependency. | CLOSED |

## Feasibility against `c0693e12`

### Operator zoom

**Feasible.** The baseline already creates a Chromium M150 `ZoomController` for
the primary Headless `WebContents`, and `OperatorControls` already owns
high-priority browser accelerators. Draft A correctly adds the direct
`//components/zoom` dependency and uses `zoom::PageZoom` rather than mutating
startup `--zoom`, viewport, device scale, window bounds, or terminal geometry.

Durability is correctly treated as Carbonyl embedder work rather than an
assumed `HostZoomMap` property. The planned `content::ZoomLevelDelegate`,
profile-pref registration, write acknowledgement, profile/host isolation, and
ephemeral no-write tests address the pinned Headless persistence gap.

### Extensions WebUI

**Feasible behind Draft B's mandatory go/no-go gate.** Chromium M150 exposes
the required WebUI configuration, data-source, Mojo, origin/binding, and
process-isolation surfaces, but Carbonyl has not yet proven them in its
Headless embedder. Draft B has measurable exit criteria for the scheme/host,
factory, packaged resources, CSP, process/origin lock, typed broker, active-page
bridge, DTO, negative binding tests, teardown, dependency cost, and ADR.

The no-go path is safe: it blocks Draft D and returns the bounded native Views
fallback for separate architecture approval rather than silently changing
scope or importing `//chrome`.

## Traceability and issue sufficiency

| Draft | Scope | Traceability | Dependency disposition | Result |
|---|---|---|---|---|
| A | Durable operator page zoom | `UC-OZ-001`, `R-OZ-01`–`R-OZ-04`, `R-QA-01`, zoom/persistence/Xorg suites | Independent; #190/#288/#301/#99/#307 are related history | READY |
| B | Secure WebUI architecture spike | Architecture delivery gate 2, `R-EX-01`, `R-EX-04`, `R-EX-06`, security screening | Independent gate; #156 is parent and #285/#290 are context | READY |
| C | Popup/options defect hardening | Delivered #290 contract, `R-EX-02`, `R-EX-06`, `R-EX-07`, hostile/lifecycle suites | Independent follow-up to closed #290/#306; prerequisite for D action/options | READY |
| D | Basic extensions center | `UC-OZ-002`, `UC-OZ-003`, `R-EX-01`–`R-EX-07`, policy/accessibility/teardown suites | Depends only on accepted B ADR and completion of C; #156 is parent | READY |

The dependency graph is acyclic:

```text
Wave 1: A        B (go/no-go ADR)        C
                 \                     /
                  +-------> D <--------+
```

The duplicate disposition is adequate:

- Draft A is new operator page-zoom work; broad #190 remains related only.
- Drafts B/D are scoped children/usability work under open epic #156 and do not
  restate the completed MV3 runtime or restart-management implementation.
- Draft C explicitly reconciles the delivered popup/options acceptance gap as
  a defect/security follow-up to #290/#306.
- Broad `tabs`, `webNavigation`, and `commands` compatibility remains with
  #156 and is not duplicated here.

## Filing conditions

The corpus may proceed to human approval with these conditions preserved:

1. Approval explicitly confirms browser-owned HTML/CSS/JS management UI and
   durable per-host zoom for persistent profiles.
2. Draft B is filed and resolved as a go/no-go gate; Draft D is not started on
   a no-go result.
3. Draft D does not expose popup/options operations until Draft C is complete.
4. Tracker bodies are policy-composed from the reviewed exact drafts without
   weakening acceptance criteria, non-goals, security boundaries, or links.
5. Browser/display/GPU/input acceptance remains restricted to the fail-closed
   disposable Ubuntu 24.04/26.04 Xorg route, never Titan's host session.

Subject to the mandatory human approval above, the issue set is **READY** for
filing.
