# issues #168 / #211 - native select and click classification

This repro classifies the shared failure mode behind:

- `#168` / upstream `fathyb#94`: Google language options are not clickable
- `#211` / upstream `fathyb#184`: dropdowns do not work

The fixture exposes two large hit targets. The verifier first clicks a normal
button, then clicks a native `<select>`, then sends `ArrowDown` + `Enter`.
Browser state is reflected through `document.title`, which Carbonyl emits as an
OSC title sequence, so the check does not depend on GPU pixels.

Run:

```sh
CARBONYL_BIN=/path/to/carbonyl test/repro/issue-168-211/run.sh
```

Interpretation:

- Button click fails: ordinary mouse coordinate/click mapping is suspect.
- Button click passes but select focus/mousedown fails: select hit targeting is
  suspect.
- Select is reached but `ArrowDown` + `Enter` does not change it: native
  select/popup keyboard handling is suspect.
- Full pass: this local fixture does not reproduce the upstream dropdown class;
  the next step is a site-specific repro.
