# Research Spike: Sixel / Terminal Image-Protocol Output

**Status**: Draft (spike — investigation only, no implementation)
**Date**: 2026-06-23
**Author**: roctinam
**Tracks**: roctinam/carbonyl#241 (`feat(render): sixel / terminal image-protocol output`)
**Upstream**: fathyb/carbonyl#11 ("Consider Sixel Support", 2023-01-28, original request) and fathyb/carbonyl#210 (later, larger sixel thread — the most-requested feature)
**Constrains / amends**: @.aiwg/architecture/adr-005-terminal-rendering-approach.md (in-process quadrant renderer is and stays the default)
**Sibling backend (precedent)**: @src/output/framebuffer.rs + @docs/framebuffer-backend.md (#125)

## Purpose

#241 proposes adding sixel (and ideally kitty/iTerm2) image-protocol output so Carbonyl renders true images in capable terminals instead of the 2×2 Unicode-quadrant approximation. ADR-005 already rejected sixel-as-default for sound reasons (terminal coverage, dependency cost). This spike de-risks the **opt-in backend** framing before any implementation issue is opened: it answers the open technical questions, fixes the integration shape, and sets explicit go/no-go criteria. It is investigation only — it ships no renderer code.

## Audit trail (why this spike exists, not a new issue)

fathyb#11 is the original sixel request (author account deleted, open, label `enhancement`, no comments). fathyb#210 is a later thread asking for the same thing with five named requesters. Our fork already tracks the topic as **#241**, currently cross-referenced to fathyb#210 only. fathyb#11 is an upstream duplicate of the same ask; no new Gitea issue is warranted. Recommended housekeeping (separate from this spike): add the fathyb#11 reference and the `upstream-map` label to #241 so the original request is traceable.

## Questions this spike must answer

1. **Capability detection** — how does Carbonyl learn at runtime that the attached terminal supports sixel (and/or kitty/iTerm2), and what is the fallback when it cannot tell?
2. **Encoder approach** — vendor a C sixel library (e.g. libsixel) or write a small in-tree Rust encoder? ADR-005's "no new C dependency" constraint pushes toward in-tree; what does that cost?
3. **Integration point** — where in the existing frame pipeline does a sixel sink attach, and can it reuse the #125 backend pattern verbatim?
4. **Performance** — sixel output is far larger per frame than quadrant cells; is it viable at interactive fps, or is it a "render on demand / low-fps" feature?
5. **Scope boundary** — does this stay strictly additive (quadrant default preserved per ADR-005), and what is the minimum shippable slice?

## Background (verified against current source)

### Current renderer

ADR-005 records the accepted approach: an in-process Unicode-quadrant renderer in `src/output/` (~1000 lines), 2×2 pixels → 1 cell, 24-bit or 256-color ANSI. Sixel/kitty/iTerm2 were considered and rejected **for the default path** because terminal coverage is uneven and a fallback renderer would be needed anyway. #241 does not contest that — it keeps the quadrant renderer as default and adds sixel as an opt-in sink. This spike inherits that constraint: sixel is additive, never a replacement.

Note: `src/output.rs` currently has `kd_tree` and `quantizer` modules commented out at the module declaration (lines 1–2). A palette-based encoder (sixel needs ≤256 color registers) may want quantization; whether to revive those modules or carry a sixel-local quantizer is an open encoder-design question (see Q2).

### Frame pipeline (where a sink attaches)

`src/output/render_thread.rs` runs a dedicated render thread (`RenderThread::boot`): a `FrameSync` paces to `--fps`, Chromium pushes frame closures over an mpsc channel that mutate a `Renderer`, and `renderer.render()` is called once per due frame. The source raster Chromium hands the bridge is **BGRA8888** (confirmed in `src/output/framebuffer.rs` header and `blit_bgra_into`). So any new backend consumes the same BGRA raster + damage rect that the framebuffer backend already takes.

### The #125 framebuffer backend is the precedent pattern

`src/output/framebuffer.rs` is a self-contained output sink that:

- takes the same BGRA8888 raster + damage `Rect`,
- has a **pure, unit-tested conversion core** (`blit_bgra_into`) with no device I/O,
- is gated behind a CLI flag (`--framebuffer`) and `#![allow(dead_code)]` until wired,
- documents explicitly that landing the encoder/converter and wiring it into the live render path are **separate cycles**, the second requiring the full Chromium build to verify.

This is the template for sixel: land a pure, unit-tested `bgra → sixel DCS` encoder first; wire it behind `--sixel` (or auto-detect) as a follow-up. It de-risks the encoder independently of the expensive Chromium build (cf. memory: full build-runtime is the real gate).

### Capability detection has a home

Sixel emission is itself a DCS sequence (`DCS q … ST`). Carbonyl already runs a DCS parser on the **input** side: `src/input/dcs/parser.rs` dispatches `0`/`1` then `$` (status/DECRQSS) or `+` (resource/XTGETTCAP). Capability negotiation (send Primary Device Attributes `CSI c`, read back the response, look for `;4` = sixel in the DA1 attribute list) extends this existing input-parsing machinery rather than introducing a new mechanism. kitty/iTerm2 use their own detection handshakes — out of scope for the minimum slice but the same input-parsing seam applies.

## Proposed investigation plan (spike tasks)

Agent-oriented scope (no wall-clock estimates per project convention). Each task is independently verifiable.

| # | Task | Exit artifact |
|---|------|---------------|
| S1 | Confirm DA1 round-trip: emit `CSI c`, capture a real terminal's reply, locate the sixel `4` attribute; verify our input DCS/CSI path can observe it. | Note + captured bytes from 2–3 terminals (xterm, foot, WezTerm/kitty) |
| S2 | Spike a pure Rust `bgra_to_sixel(src, size, damage) -> Vec<u8>` encoder (palette-quantize to ≤256 registers, emit `DCS q … ST`). No wiring. Unit-test against a tiny known raster, decode/eyeball in a sixel terminal. | Throwaway encoder + 3–4 unit tests + one screenshot |
| S3 | Measure encoded-frame size and encode time for a representative web page raster at typical viewport. Compare against quadrant-cell byte volume. | Size/time table; viability verdict for interactive fps |
| S4 | Decide encoder sourcing: in-tree Rust vs vendored libsixel, scored against ADR-005's no-new-C-dependency constraint, CVE surface, and S3 performance. | Decision-matrix entry feeding a new ADR |
| S5 | Define the minimum shippable slice and the CLI/auto-detect surface (`--sixel` explicit vs DA1 auto with quadrant fallback). | Implementation-issue draft for #241 |

S1, S2, S3 are independent and parallelizable. S4 depends on S2+S3. S5 depends on S4.

## Decision criteria (spike exit / go-no-go)

- **GO to implementation** if: a pure in-tree Rust encoder is tractable at a size/time budget that supports at least low-fps interactive use, capability detection is reliable with a clean quadrant fallback, and the slice stays strictly additive to ADR-005.
- **NO-GO / defer** if: acceptable fidelity requires vendoring a C library (re-opens the ADR-005 dependency rejection — escalate as an explicit ADR decision, not an implementation default), or per-frame cost forces sub-1-fps output with no on-demand mode that users actually want.
- **PARTIAL**: ship a "render current frame as sixel on a keybind / on demand" capability (cheap, high-value for image-heavy pages) even if continuous sixel is not viable — this still satisfies fathyb#11 and #210's core ask.

## Risks

1. **Performance** — sixel frames are an order of magnitude larger than quadrant cells; continuous rendering may saturate the TTY. Mitigation: on-demand / low-fps mode (the PARTIAL outcome).
2. **Dependency creep** — libsixel would reverse ADR-005's deliberate no-C-dependency stance. Mitigation: in-tree Rust encoder default; vendoring requires an explicit superseding ADR.
3. **Capability false-positives** — terminals that advertise sixel but render it poorly. Mitigation: keep quadrant as default; sixel opt-in or clearly-fallback-on-failure.
4. **Build gate** — the encoder can be developed and unit-tested ABI-neutral (Rust-only, like #125's pure core), but live wiring needs the full Chromium build to verify. Plan the spike so S1–S3 need no Chromium rebuild.

## Reasoning

1. **Problem analysis**: The ask (fathyb#11/#210, #241) is real-image rendering in capable terminals. The constraint (ADR-005) is "don't regress the universally-compatible default and don't add a C dependency." The spike exists to find whether those can both hold.
2. **Constraint identification**: additive-only; in-tree-preferred; must survive on terminals without sixel; encoder must be developable without the expensive Chromium build to keep iteration cheap.
3. **Alternative consideration**: (a) vendored libsixel — fast to fidelity, violates ADR-005 dependency stance; (b) in-tree Rust encoder — aligns with ADR-005, unknown effort/fidelity, which is exactly what S2/S3 measure; (c) on-demand-only sixel — cheapest, sidesteps the fps problem, still satisfies the core ask.
4. **Decision rationale**: Model the work on the proven #125 framebuffer pattern (pure unit-tested core, flag-gated, wired later) so the encoder is de-risked independently of Chromium and the ADR-005 default is never touched.
5. **Risk assessment**: performance and dependency creep are the two that can flip the verdict to NO-GO; both have a PARTIAL escape hatch (on-demand sixel) that still delivers user value.

## References

- @.aiwg/architecture/adr-005-terminal-rendering-approach.md — current renderer decision; sixel deferred as default
- @src/output/framebuffer.rs — #125 backend; the precedent pattern for an additive flag-gated sink
- @docs/framebuffer-backend.md — #125 narrative + cycle split (encoder first, wiring later)
- @src/output/render_thread.rs — frame pipeline / where a sink attaches
- @src/output.rs — output module surface (note: `kd_tree`/`quantizer` currently commented out)
- @src/output/quad.rs — quadrant glyph + color binarization (the default path sixel sits beside)
- @src/input/dcs/parser.rs — existing DCS parser; capability-negotiation seam for DA1
- roctinam/carbonyl#241 — tracking issue
- fathyb/carbonyl#11, fathyb/carbonyl#210 — upstream requests
- Sixel: DEC STD 070 / `DCS q … ST`; DA1 sixel attribute = `4` in the `CSI c` reply
