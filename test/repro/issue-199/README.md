# issue #199 — right-click forwards the right mouse button

Verifies the mouse-button FFI widening (Stage 2a of #231): a terminal SGR
right-button click must reach Blink as `button == 2` and fire a `contextmenu`,
instead of being delivered as a left click (the prior behaviour — the C++ side
hardcoded `event.button = kLeft`).

## How it works (GPU-independent)
`fixture.html` reflects `mousedown`/`contextmenu` into `document.title`, which
Carbonyl emits as an OSC sequence (see issue-169 README). `verify.py` injects
an SGR right-button press+release (`\x1b[<2;10;10M` / `m`) and watches for
`RC:ctx:2`.

- **Exit 0 / PASS** — `RC:ctx:2` seen (right button delivered, contextmenu fired).
- **Exit 1 / FAIL** — no contextmenu with button 2. Prints observed titles, and
  distinguishes "button arrived (RC:md:2) but no contextmenu" from "delivered as
  the wrong button".
- **Exit 2 / SETUP-FAIL** — page never reached `RC:ready`.

## Requirements
A runtime carrying patch 0009 with the widened `mouse_up/mouse_down(x,y,button)`
FFI. The bundled `alpha.1` runtime predates it → right-click delivered as left
→ **FAIL** (the "before" control). A post-Stage-2a runtime → **PASS**.

## Run
```bash
CARBONYL_BIN=/path/to/runtime/carbonyl ./run.sh
```
