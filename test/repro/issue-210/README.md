# Repro harness — issue #210 (upstream fathyb#181)

> "Blank after showing the web page for ~1 second in my docker container."

A GPU-less container harness that reproduces the *conditions* of the bug and
gives a ground-truth **blank-vs-content** verdict for the prebuilt carbonyl
binary.

## Why this exists

Two things make this bug easy to mis-diagnose:

1. **GPU-less environment matters.** The report is docker-specific, so the
   harness uses a clean `debian:bullseye-slim` with no GPU drivers, exercising
   the software-rendering (SwiftShader) fallback path.
2. **"Stopped emitting frames" ≠ "blank screen."** carbonyl paints to the
   terminal on damage and goes idle once the page settles — the terminal keeps
   the last frame. A naive "no new output after 1s" check reads that idle state
   as a blank and produces a false positive. The reliable signal is the **color
   diversity of the final screen buffer**, recovered by replaying the captured
   ANSI stream through a terminal emulator (`pyte`). A blank page collapses to
   ~1–3 distinct `(fg,bg)` pairs; a rendered page has many, including real text
   colors.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Clean GPU-less runtime image with the **complete** load-time lib set |
| `probe.py`   | Runs carbonyl in the container, captures the raw ANSI stream |
| `analyze.py` | Replays the capture through `pyte`, reports the blank-vs-content verdict |
| `run.sh`     | Builds the image, probes, analyzes (exit 0 = content, 1 = blank) |

## Usage

```bash
pip install pyte
cd test/repro/issue-210
./run.sh ../../../build/pre-built/x86_64-unknown-linux-gnu \
         https://en.wikipedia.org/wiki/Chromium_(web_browser)
```

## Result (2026-06-18, carbonyl 0.2.0-alpha.1, x86_64)

**Not reproduced.** Across a heavy-DOM page (Wikipedia) and a WebGL page
(get.webgl.org), the page renders and the final screen shows content
(174 and 9 distinct colors respectively, including black-on-white text) — not a
uniform blank. The fork bundles SwiftShader (`libvk_swiftshader.so`,
`libvulkan.so.1`, `vk_swiftshader_icd.json`) and falls back to software
rendering in a GPU-less container, which appears to handle the upstream
condition.

Limitations: single base image (`bullseye`), x86_64, headless pty, two page
classes. Not exhaustive across arm64, other base images, or WebGL-canvas-heavy
apps. If a specific page/config does blank, pass it to `run.sh` — a `BLANK`
verdict (exit 1) confirms a real repro.

## Related

- Issue #210 (this repo) / upstream fathyb/carbonyl#181
- Issue #224 — the top-level `Dockerfile` lib set is incomplete; this harness's
  `Dockerfile` carries the full set.
