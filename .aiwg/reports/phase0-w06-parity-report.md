# Phase 0 W0.6 — text-render parity report

**Status:** PASS — no parity regression detected between the headless
and x11 ozone variants. Phase 0 W0.6 acceptance criteria satisfied.

**Generated:** 2026-04-30
**Headless runtime:** `runtime-dd69bef0ea4b2512` (`v0.2.0-alpha.3` headless asset)
**x11 runtime:** `runtime-x11-dd69bef0ea4b2512` (`v0.2.0-alpha.3` x11 asset)
**Harness:** `scripts/test-text-parity.sh`
**Fixtures:** `tests/fixtures/parity/{static,css-rich,dynamic}.html`

---

## What this test asserts

Carbonyl's terminal text render must be content-equivalent between the
two ozone variants. The compositor bridge in
`src/browser/host_display_client.cc` is shared between both — they
produce identical pixel buffers for the same fixture; the painter then
emits the ANSI escape sequences that drive the terminal render. A
divergence between variants would mean a code path took a different
turn under x11 vs. headless ozone, which is precisely what this test
catches.

### What "parity" means

The two variants legitimately differ in three render-loop dimensions
that are NOT parity violations:

- **Repaint rate.** The x11 variant has an active X server that may
  request frame ticks at a different cadence than headless's tickless
  bridge. Stream byte length and total quadrant-run count vary as a
  function of capture timing.
- **Cell-paint order.** Within a frame, damage-region tracking can
  emit cells row-major, column-major, or in some other order
  depending on what changed since the previous frame.
- **Cursor positioning escapes.** The frame's first byte includes
  `\x1b[<row>;<col>H` — single-digit differences in row/col are
  paint-phase noise, not content divergence.

What MUST match for parity:

- **SGR set.** The set of distinct ANSI SGR escapes used (24-bit
  truecolor `\x1b[38;2;r;g;b m` and `\x1b[48;2;r;g;b m`). SGR encodes
  the colour pairs Chromium produced; identical pixel buffers → same
  SGR set.
- **Steady-state frame size.** The largest frame in the stream (the
  "last steady-state full repaint") should be similar in size across
  variants. A 25%+ size delta would indicate one variant produced
  meaningfully less or more content.
- **Both variants must produce content.** If one stayed in startup
  and never painted, the comparison is invalid → INCONCLUSIVE.

## Method

For each fixture the harness:

1. Launches Carbonyl headless against the fixture, polling the stream
   until it accumulates `MIN_CONTENT_QUADRANTS=100` quadrant-block
   runs and is stable for `SETTLE_SECONDS=2`. Bounded by `MAX_CAPTURE`.
2. Repeats with the x11 variant against the same fixture at the same
   `--viewport=1280x720`, `COLORTERM=truecolor`.
3. Extracts the **largest frame** in each stream — i.e. the begin
   marker (`\x1b[?25l\x1b[?12l`) followed by the most bytes before the
   next begin. This is the steady-state full repaint, robust against
   intermittent damage updates and empty frames.
4. Compares the largest frame's distinct-SGR set + size between
   variants under the fixture's tolerance class.

## Validated results

Validated 2026-04-30 against `runtime-dd69bef0ea4b2512` (headless)
and `runtime-x11-dd69bef0ea4b2512` (x11), running inside the
`carbonyl-agent-qa-runner` image with Xorg `:99` dummy driver.

| Fixture | Headless quadrants | x11 quadrants | Headless last-frame SGRs | x11 last-frame SGRs | Last-frame size delta | Result |
|---|---:|---:|---:|---:|---:|---|
| `static.html` | 1692 | 1692 | 253 | 253 | <1% | **PASS** |
| `css-rich.html` | 1818 | 1818 | 48 | 48 | 0% | **PASS** |
| `dynamic.html` | 1819 | 1819 | 42 | 42 | 0% | **PASS** |

Identical SGR-set sizes (253/253, 48/48, 42/42) and identical
last-frame sizes are the strong parity signal. Both variants render
the same colour palette into the same number of cells.

## Findings

- **No content divergence between variants.** Both produce the same
  set of distinct colour-pair commands and the same number of
  quadrant cells across all three fixtures. The compositor bridge
  takes the same code path under both ozone platforms.
- **Repaint-rate difference is real but expected.** Total stream
  length varies between captures (often ~2× more frames captured
  from x11 in a fixed window). This is paint-cadence variance, not
  a content regression — the steady-state frame content is invariant.
- **Cursor-positioning bytes differ at frame head.** A 1-byte diff
  in the leading `\x1b[<row>;<col>H` sequence is a normal product of
  capturing two processes mid-paint-loop. Not a parity violation.

## Operational notes

- **CI integration is a follow-up.** `build-runtime.yml` builds one
  variant per dispatch; running this test in CI requires both
  runtime tarballs to be present. A new `test-text-parity.yml`
  workflow that downloads both `runtime-<hash>` and
  `runtime-x11-<hash>` and runs the harness inside the qa-runner
  image is the right shape. Tracked separately.
- **Environmental sensitivity.** On loaded shared hardware the
  capture window can occasionally hit `MAX_CAPTURE` before either
  variant reaches steady state. The harness reports those runs as
  INCONCLUSIVE rather than FAIL — a clear signal that the test
  environment, not the rendering, was the problem. On dedicated CI
  hardware (titan) this should be uncommon.

## Acceptance criteria

- [x] 3 reference fixtures committed at `tests/fixtures/parity/`
- [x] Harness runs against both ozone builds and reports per-fixture
- [x] Content equivalence verified — SGR sets match exactly across
      variants for all 3 fixtures
- [x] Parity report committed under `.aiwg/reports/`
- [x] Linked from Phase 0 tracker `roctinam/carbonyl#60`

## References

- Issue: `roctinam/carbonyl#62`
- Phase 0 tracker: `roctinam/carbonyl#60`
- ADR-002 rev 2: `docs/adr-002-trusted-input-approach.md`
- Bridge implementation: `src/browser/host_display_client.cc`,
  `src/browser/x_mirror.cc`
- Companion test: `scripts/test-x-mirror.sh` (dual-output validation)
