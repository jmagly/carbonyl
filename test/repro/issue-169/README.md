# issue #169 — TAB key advances form focus

Verifies the fix in chromium patch 0009 (`OnKeyPressInput`: `0x09 -> VKEY_TAB`,
PR #232 / commit `201be82`): with Carbonyl's opt-in `CARBONYL_TAB_FOCUS=1`
setting, pressing TAB in a multi-field form must advance focus to the next field
instead of inserting a literal tab character into the current field's value.

## How it works (GPU-independent)

`fixture.html` reflects the focused field id into `document.title` on every
`focusin`. Carbonyl emits the page title as an OSC control sequence on stdout
(`src/output/renderer.rs` `set_title` → `\x1b]0;{title}\x07`), so the harness
observes focus changes directly from the terminal byte stream — no pixel
capture, no GL/Xvfb. This sidesteps the headless-GPU rendering caveat that
makes pixel-based harnesses (e.g. issue-87) environment-sensitive.

`verify.py`:
1. Waits for load + autofocus → title `CFOCUS:f0`.
2. Sends `TAB` (`0x09`) → expects `CFOCUS:f1` (focus advanced).
3. Sends `TAB` again → expects `CFOCUS:f2`.

- **Exit 0 / PASS** — focus advanced on TAB (fix present).
- **Exit 1 / FAIL** — focus did not advance (fix absent/regressed; TAB was
  swallowed as text).
- **Exit 2 / SETUP-FAIL** — the page never reached `CFOCUS:f0` (the runtime
  could not load/run the fixture in this environment).

## Requirements

- A Carbonyl runtime that carries chromium patch 0009 with the
  `0x09 -> VKEY_TAB` case — i.e. a runtime built from `main` at/after
  `201be82`. The harness sets `CARBONYL_TAB_FOCUS=1` because Tab focus
  traversal is now intentionally opt-in (#242). The bundled `alpha.1` pre-built
  runtime predates the fix and will FAIL (that is the expected "before" result).
- `python3`, a PTY (standard on Linux), and the runtime's shared-lib deps.
- Runs in terminal/headless mode (`--no-sandbox --disable-gpu`); no X server
  required.

## Run

```bash
CARBONYL_BIN=/path/to/post-201be82/carbonyl ./run.sh
# or rely on the default build/pre-built path (must be a post-fix runtime)
```

## Before/after

Run against the bundled `alpha.1` runtime → **FAIL** (TAB inserted as text).
Run against a post-`201be82` runtime → **PASS** (focus advances). The delta is
the verification.
