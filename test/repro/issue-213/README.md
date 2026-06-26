# Issue #213 PDF Rendering Repro

This harness checks whether Carbonyl can surface text from an embedded PDF,
matching the Overleaf preview failure shape without relying on Overleaf.

It serves:

- `fixture.html` - a normal HTML page with an iframe and object pointing at
  `sample.pdf`
- `sample.pdf` - a tiny one-page PDF containing the text
  `Carbonyl PDF fixture text`

Run:

```sh
test/repro/issue-213/run.sh
```

Exit codes:

- `0` - PDF text is visible through Carbonyl output
- `1` - wrapper HTML loaded but PDF text is not visible
- `2` - harness/runtime setup failed

Useful environment variables:

- `CARBONYL_BIN` - Carbonyl binary to test
- `ISSUE213_TIMEOUT` - command timeout in seconds, default `30`
- `ISSUE213_IDLE_MS` - dump-text idle wait, default `3000`
- `ISSUE213_CAPTURE_SECONDS` - terminal capture window, default `8`
