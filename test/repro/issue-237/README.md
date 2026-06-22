# issue #237 — Shift+Tab reverses form focus (key modifier mask in input FFI)

Verifies the fix for #237 (follow-up to the #231 input-event FFI epic): key
**modifiers** now survive the FFI boundary, so Shift+Tab reverses form focus
instead of being swallowed. Before #237, `key.modifiers` was parsed but dropped
when `bridge.rs` forwarded only the codepoint to `key_press`; the page never saw
`shiftKey`, so Blink's `DefaultTabEventHandler` never ran reverse traversal.

The fix has two halves:

1. **FFI widening** — `key_press` now carries `(codepoint, modifier_mask)`
   (`src/browser/bridge.rs`, `src/browser/renderer.h`, chromium patch 0009).
   The C++ side translates the carbonyl mask (bit0 shift, bit1 control, bit2
   alt, bit3 meta — `KeyModifiers::mask`) into `blink::WebInputEvent::Modifiers`
   before `ForwardKeyboardEvent`. This restores **all** parsed modifiers
   (Shift/Ctrl/Alt/Meta) for arrow keys and Tab.
2. **CSI Z decode** — xterm sends a bare back-tab `ESC [ Z` (terminfo `kcbt`)
   for Shift+Tab. `src/input/parser.rs` decodes it to Tab (`0x09`) with the
   shift modifier set so the FFI has a modifier to forward.

The invert-color shortcut (`modifier + Up`, #181) is unaffected: the renderer
still intercepts it before the FFI dispatch, so its consumption is preserved.

## How it works (GPU-independent)

Identical observation channel to issue-169: `fixture.html` reflects the focused
field id into `document.title` on every `focusin`, and Carbonyl emits the title
as an OSC sequence on stdout (`src/output/renderer.rs` `set_title` →
`\x1b]0;{title}\x07`). The harness reads focus transitions straight from the
terminal byte stream — no pixel capture, no GL/Xvfb.

`verify.py`:
1. Waits for load + autofocus → `CFOCUS:f0`.
2. `TAB` (`0x09`) → `CFOCUS:f1`, `TAB` → `CFOCUS:f2` (forward sanity; this is
   the issue-169 path and must work first).
3. `Shift+Tab` (`ESC [ Z`) → `CFOCUS:f1` (**reverse** — the #237 fix).
4. `Shift+Tab` again → `CFOCUS:f0` (reverse is repeatable, not a one-off).

- **Exit 0 / PASS** — Shift+Tab reversed focus (fix present).
- **Exit 1 / FAIL** — forward TAB worked but Shift+Tab did not reverse (modifier
  dropped at the FFI, or CSI Z not decoded — fix absent/regressed).
- **Exit 2 / SETUP-FAIL** — page never loaded, or forward TAB itself is broken
  (so reverse focus cannot be evaluated).

## Requirements

- A Carbonyl runtime **built from a tree carrying the #237 changes** — both the
  widened patch 0009 `key_press`/`OnKeyPressInput` *and* the parser CSI Z decode.
  A pre-#237 runtime FAILs (the expected "before" result). This requires a full
  `build-runtime` cycle; the Rust half alone (hot-swapped `libcarbonyl.so`)
  is **not** sufficient because the FFI arity and the C++ modifier translation
  live in patch 0009.
- `python3`, a PTY (standard on Linux), and the runtime's shared-lib deps.
- Terminal/headless mode (`--no-sandbox --disable-gpu`); no X server required.

## Run

```bash
CARBONYL_BIN=/path/to/post-237/carbonyl ./run.sh
# or rely on the default build/pre-built path (must be a post-#237 runtime)
```

## Before/after

Run against a pre-#237 runtime → **FAIL** (Shift+Tab does nothing / stays put).
Run against a post-#237 runtime → **PASS** (focus reverses f2→f1→f0). The delta
is the verification.
