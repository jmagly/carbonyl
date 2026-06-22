# issue #178 (Cyrillic) / #217 (Chinese) — non-ASCII input

Verifies the UTF-8 input fix (Stage 3 of #231): a terminal delivers composed /
non-ASCII text as multi-byte UTF-8 on stdin, and it must reach the page as the
intended Unicode character. Previously `key_press` was a single `c_char`, so
each UTF-8 byte became its own broken keypress.

## How it works (GPU-independent)
`fixture.html` reflects the focused input's value into `document.title`;
Carbonyl emits the title as a UTF-8 OSC sequence (see issue-169 README).
`verify.py` types 'д' (U+0434) then '中' (U+4E2D) as raw UTF-8 bytes and checks
the value becomes `д` then `д中`.

- **Exit 0 / PASS** — both characters landed intact.
- **Exit 1 / FAIL** — value wrong (prints observed titles).
- **Exit 2 / SETUP-FAIL** — page never reached READY.

## Requirements
A runtime carrying the codepoint key FFI (Stage 3). The bundled `alpha.1`
runtime predates it → non-ASCII input is garbled → **FAIL** (the control).

## Run
```bash
CARBONYL_BIN=/path/to/runtime/carbonyl ./run.sh
```
