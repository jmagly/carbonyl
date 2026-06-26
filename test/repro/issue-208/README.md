# Issue #208 File Dialog Repro

This harness verifies `--file-dialog-path` against the File System Access API.

It serves a local page with a button that calls `showOpenFilePicker()`, then
drives Carbonyl through a PTY click and watches OSC title updates from the page.

Run:

```sh
test/repro/issue-208/run.sh
```

Exit codes:

- `0` - the picker resolves to the configured file
- `1` - the page loads but the picker does not resolve
- `2` - harness/runtime setup failed
