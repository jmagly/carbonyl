# Issue 241 Terminal Image Measurements

Captured on 2026-07-02 with the local x86_64 pre-built runtime after
`scripts/build-local.sh` rebuilt and installed the current `libcarbonyl.so`.
The sixel numbers below include the band-active plane skip and repeated-column
RLE optimization added after the first measurement pass.

Command shape:

```bash
IDLE_MS=1000 test/repro/issue-241/measure.sh
IDLE_MS=1000 test/repro/issue-241/measure.sh https://example.com
```

Viewport: `1280x800`

## Results

| Page | Format | Source BGRA bytes | PNG bytes | Encoded bytes | Sixel colors | Palette mode |
|---|---:|---:|---:|---:|---:|---|
| `fixture.html` | sixel | 4,096,000 | n/a | 133,180 | 256 | RGB332 |
| `fixture.html` | kitty | 4,096,000 | 851,554 | 1,135,440 | n/a | n/a |
| `fixture.html` | iterm2 | 4,096,000 | 851,554 | 1,135,478 | n/a | n/a |
| `https://example.com` | sixel | 4,096,000 | n/a | 7,321 | 256 | RGB332 |
| `https://example.com` | kitty | 4,096,000 | 27,009 | 36,044 | n/a | n/a |
| `https://example.com` | iterm2 | 4,096,000 | 27,009 | 36,082 | n/a | n/a |

## Notes

- The fixture deliberately performs a delayed repaint so dump-mode idle waits
  for a settled, painted frame instead of an early uniform frame.
- The first measurement pass produced about 44 MB sixel payloads for high-color
  `1280x800` frames because RGB332 fallback emitted 256 full color planes for
  every six-row band. The current encoder skips palette planes absent from each
  band and uses sixel repeat runs for repeated columns.
- The optimized sixel fixture payload is now smaller than the PNG-wrapped
  kitty/iTerm2 payload for this synthetic page. Real pages still vary by color
  distribution and compressibility, so live sixel remains opt-in/DA1-gated.
- Kitty and iTerm2 dumps are much smaller because they carry PNG payloads inside
  terminal image protocol wrappers.
- Generated payloads and logs live under `.aiwg/measurements/issue-241/` during
  local runs and are intentionally gitignored.

## WezTerm Live Image Smokes

Captured on 2026-07-02T00:03:41-04:00 with
`wezterm 20240203-110809-5046fc22`.

Sixel command:

```bash
test/repro/issue-241/smoke-wezterm-sixel.sh
```

Sixel result:

```text
PASS: captured WezTerm sixel smoke window 83886083
.aiwg/measurements/issue-241/wezterm-sixel-smoke.ppm: PPM raw, 1558 by 1140 maxval 255
capture=.aiwg/measurements/issue-241/wezterm-sixel-smoke.png
```

Kitty command, captured on 2026-07-02T00:08:00-04:00 after rebuilding the local
runtime:

```bash
MODE=kitty test/repro/issue-241/smoke-wezterm-sixel.sh
```

Kitty result:

```text
PASS: captured WezTerm kitty smoke window 98566147
.aiwg/measurements/issue-241/wezterm-kitty-smoke.ppm: PPM raw, 1558 by 1140 maxval 255
capture=.aiwg/measurements/issue-241/wezterm-kitty-smoke.png
```

iTerm2-protocol command, captured on 2026-07-02T00:10:09-04:00 in WezTerm:

```bash
MODE=iterm2 test/repro/issue-241/smoke-wezterm-sixel.sh
```

iTerm2-protocol result:

```text
PASS: captured WezTerm iterm2 smoke window 83886083
.aiwg/measurements/issue-241/wezterm-iterm2-smoke.ppm: PPM raw, 1558 by 1140 maxval 255
capture=.aiwg/measurements/issue-241/wezterm-iterm2-smoke.png
```

The smoke script runs Carbonyl live terminal-image mode inside a fresh WezTerm
GUI window, captures that window with `xwd`, converts it through Netpbm to PNG,
and fails if the capture is missing or empty. The generated `.xwd`, `.ppm`,
`.png`, and log files are ignored under `.aiwg/measurements/issue-241/`.
The `MODE=iterm2` run verifies Carbonyl's iTerm2 inline-image escape path in a
terminal that supports that protocol; it is not a native macOS iTerm2 GUI run.

Auto-selector commands, captured on 2026-07-02T00:22:00-04:00 after rebuilding
the local runtime:

```bash
MODE=auto-kitty test/repro/issue-241/smoke-wezterm-sixel.sh
MODE=auto-iterm2 test/repro/issue-241/smoke-wezterm-sixel.sh
MODE=auto-sixel test/repro/issue-241/smoke-wezterm-sixel.sh
```

Auto-selector results:

```text
PASS: captured WezTerm auto-kitty smoke window 83886083
.aiwg/measurements/issue-241/wezterm-auto-kitty-smoke.ppm: PPM raw, 1558 by 1140 maxval 65535
capture=.aiwg/measurements/issue-241/wezterm-auto-kitty-smoke.png

PASS: captured WezTerm auto-iterm2 smoke window 100663299
.aiwg/measurements/issue-241/wezterm-auto-iterm2-smoke.ppm: PPM raw, 1558 by 1140 maxval 255
capture=.aiwg/measurements/issue-241/wezterm-auto-iterm2-smoke.png

PASS: captured WezTerm auto-sixel smoke window 98566147
.aiwg/measurements/issue-241/wezterm-auto-sixel-smoke.ppm: PPM raw, 1558 by 1140 maxval 255
capture=.aiwg/measurements/issue-241/wezterm-auto-sixel-smoke.png
```

The `MODE=auto-kitty` run injects `KITTY_WINDOW_ID=1` and verifies
`--terminal-image=auto` selects the kitty protocol. The `MODE=auto-iterm2` run
injects `TERM_PROGRAM=iTerm.app` and verifies the same auto flag selects the
iTerm2 inline-image protocol. The `MODE=auto-sixel` run uses no injected
kitty/iTerm2 marker and verifies the auto flag falls back to DA1-gated sixel in
WezTerm.
