# Carbonyl runtime modes

Carbonyl ships one binary that supports three deployment modes. The mode
is chosen at runtime via the underlying Chromium ozone platform plus a
small set of Carbonyl-specific environment variables — there is no
"x11 build" vs "headless build" distinction at the asset level (a
single tarball can run any mode the host can support).

This document is the operator reference: pick the row that matches
your use case, copy the invocation, and skim the session-portability
notes before switching modes mid-engagement.

---

## TL;DR — pick a mode

| Use case | Mode | Inputs | Visual capture | Network/cookies |
|---|---|---|---|---|
| Read a webpage in a tmux pane | **Terminal-only** | terminal keystrokes (`isTrusted=false`) | none | full |
| Automation against bot-detecting sites | **x11 + uinput** | kernel uinput → Xorg → Chromium (`isTrusted=true`) | none (X window stays blank) | full |
| Automation **and** screenshot/video capture | **x11 + uinput + X-mirror** | same as above | `scrot`, `ffmpeg`, `x11vnc` against `$DISPLAY` | full |

**Rule of thumb:** if you don't need bot-detection-resistant input, stay
in terminal-only mode — it has the smallest dependency surface and the
lowest fingerprint cost. Move to x11 + uinput only when you've measured
that automation events with `isTrusted=false` are being filtered. Add
the X-mirror only when an operator (human or pipeline) needs to see what
the page actually looks like, not just the terminal rasterisation.

---

## Mode 1 — Terminal-only (default)

Carbonyl renders the page to your terminal via UTF-8 quadrant blocks
and ANSI colour escapes. No X server, no uinput, no extra processes.

```bash
carbonyl https://example.com
```

**What runs:** one Carbonyl process. Stdout is the rendered surface.
Input is whatever the terminal forwards (keystrokes, mouse if the
terminal supports SGR-1006). All web events Carbonyl synthesises from
those keystrokes are JS `isTrusted: false` — same as Puppeteer or
Playwright drivers.

**Fingerprint:** standard Chromium headless surface with Carbonyl's
patches. No `automation` flags are set; ozone platform reports as
`headless`.

---

## Mode 2 — x11 + uinput (trusted input)

Carbonyl runs against a real X server (typically a containerised Xorg
with the dummy or modesetting driver). Input is delivered by writing
kernel-level event descriptors via `/dev/uinput`; the X server picks
them up via `evdev`/`libinput` and dispatches them to Carbonyl as
real X input events. JavaScript sees `isTrusted: true`.

```bash
DISPLAY=:99 carbonyl --ozone-platform=x11 https://example.com
```

In a container — see `docker/` patterns in `roctinam/carbonyl-agent`:

```bash
docker run --rm \
  --device=/dev/uinput \
  --group-add input \
  -e CARBONYL_GPU_MODE=cpu \
  carbonyl-agent-qa-runner:latest \
  carbonyl --ozone-platform=x11 https://example.com
```

**What runs:** Xorg `:99`, Carbonyl. The Carbonyl process attaches to
both the X display (for input) and stdout (for terminal rendering, which
still works). The X window itself is **not** drawn to — Carbonyl's
compositor bridge intercepts every frame before it reaches X.

**When to use:** sites that fingerprint event trust (bank logins,
e-commerce checkouts, anti-bot middleware like PerimeterX, DataDome,
Cloudflare bot management). See ADR-002 for the threat model.

**When *not* to use:** anything where you control the input pipeline
already, where event trust isn't checked, or where you want the
smallest possible runtime surface.

---

## Mode 3 — x11 + uinput + X-mirror (visual capture)

Same as Mode 2, but with `CARBONYL_X_MIRROR=1` set. Carbonyl's compositor
bridge **also** blits each frame into a real X window on `$DISPLAY` via
`XPutImage`. External tools (`scrot`, `ffmpeg`, `x11vnc`, `xdotool`) see
the page exactly as Chromium drew it.

```bash
DISPLAY=:99 \
CARBONYL_X_MIRROR=1 \
  carbonyl --ozone-platform=x11 --viewport=1280x720 https://example.com
```

The terminal rendering pipeline is unchanged — both outputs come from
the same compositor frame, the same Chromium process, the same TLS
fingerprint, the same JS state.

**When to use:**
- Visual regression suites where the assertion is on rendered pixels
- Operator dashboards (`x11vnc` of `:99` to a VNC viewer)
- Recorded automation runs (`ffmpeg -f x11grab` of `:99`)

**When *not* to use:** any deployment where the X window's visibility
matters for cost (links libX11; opens a display connection; allocates
shared memory for the XImage). The mirror is gated off by default for
exactly this reason. Headless terminal users should never set the env
var.

**Configuration:**

| Variable | Behaviour |
|---|---|
| `CARBONYL_X_MIRROR=1` | Enable. Any other value (or unset) → disabled. |
| `DISPLAY` | Required when enabled. Mirror opens this display. |
| `--viewport=WxH` | Pin the CSS viewport so framebuffer captures are size-stable across terminal-cell variation. |

---

## CLI options reference

```
carbonyl [options] [url]

  -f, --fps=<fps>            max frames per second the painter emits (default 60)
  -z, --zoom=<zoom>          CSS zoom percentage (default 100)
  --viewport=<WIDTHxHEIGHT>  override the CSS viewport Chromium lays out
                             against. Also via CARBONYL_VIEWPORT.
  -b, --bitmap               render text as quadrant bitmaps (default)
  -d, --debug                enable debug logs (also CARBONYL_ENV_DEBUG=1)
  -h, --help                 print usage
  -v, --version              print version

Plus standard Chromium flags. The ones that matter most for Carbonyl:

  --ozone-platform=headless  default; no display required
  --ozone-platform=x11       attach to $DISPLAY (mode 2 / mode 3)
  --no-sandbox               required inside most containers
  --carbonyl-b64-text        emit base64-encoded glyph stream alongside the
                             quadrant render — used for offline OCR /
                             accessibility extraction (see scripts/test-b64-text.sh)
```

## Environment variables

| Variable | Effect | Mode |
|---|---|---|
| `CARBONYL_VIEWPORT=WxH` | CSS viewport override (same as `--viewport`) | any |
| `CARBONYL_ENV_DEBUG=1` | Verbose Rust-side logging | any |
| `CARBONYL_ENV_BITMAP=1` | Force bitmap text rendering | any |
| `CARBONYL_ENV_SHELL_MODE=1` | Treat stdout as a piped shell, not a TTY | any |
| `CARBONYL_X_MIRROR=1` | Blit compositor frames to `$DISPLAY` | mode 3 only |
| `COLORTERM=truecolor` | Force 24-bit ANSI SGR in the painter (skips terminal-capability probing) | any |
| `DISPLAY=:N` | X display to attach to | mode 2 / 3 |

---

## Session portability between modes

Switching modes mid-engagement (e.g. read a page in mode 1, then
authenticate in mode 2) **does not preserve session state by default**.
Each Carbonyl invocation gets a fresh Chromium profile. To carry state
across invocations or modes, explicitly point `--user-data-dir` at the
same directory:

```bash
PROFILE=/var/lib/carbonyl/profile-acme

# Mode 1 — read
carbonyl --user-data-dir="$PROFILE" https://app.example.com

# Mode 2 — authenticate with trusted input (same cookies, same TLS session)
DISPLAY=:99 carbonyl --user-data-dir="$PROFILE" \
  --ozone-platform=x11 https://app.example.com/login
```

**What carries across modes when `--user-data-dir` is shared:**

- Cookies (HTTP and HttpOnly) and `Set-Cookie` from prior responses
- LocalStorage, IndexedDB, ServiceWorker registrations
- HTTP cache (subject to `Cache-Control` headers)
- Saved passwords (if Chromium password manager is enabled)
- Permissions (camera, mic, notifications) granted in prior runs

**What does NOT carry:**

- Open WebSocket / SSE connections (process-scoped)
- In-memory JS state (closures, timers, `window.foo`)
- TLS session tickets if Chromium chose not to persist them
- Anything held only in `sessionStorage` if you start a new tab

**Fingerprint coherence between modes:**

The X-mirror mode (#3) is specifically designed to keep fingerprint
coherence — a single Chromium process, single TLS context, single JS
realm produces both the terminal output and the X-window output.
**Switching from mode 2 to mode 3 in the same `--user-data-dir`** is
safe: same persisted state, fresh process. Bot-detection middleware
that fingerprints across requests will see continuous identity.

**Switching from mode 1 to mode 2 mid-session is risky** for the same
reason event-trust matters in the first place: if a site has already
seen `isTrusted=false` events from your IP / cookie pair, marking
subsequent events `isTrusted=true` does not retroactively heal that
signal. For high-stakes flows, start the engagement in mode 2 and stay
there.

**One ozone variant per `--user-data-dir`** is good hygiene. The
profile directory caches GPU/Skia decisions that may be specific to the
ozone platform that wrote them; mixing them works in practice but isn't
a contract. If you need to switch platforms, start with a fresh profile.

---

## Fetching a runtime tarball

`scripts/runtime-pull.sh` downloads the matching pre-built tarball
from Gitea releases. Pass `--ozone=x11` for the x11 variant; default
is headless.

```bash
# Headless runtime (default)
bash scripts/runtime-pull.sh

# x11 runtime — needed for modes 2 and 3
bash scripts/runtime-pull.sh --ozone=x11
```

The CLI flag overrides the `CARBONYL_OZONE_TAG` env var when both are
set; CI uses the env var, interactive operators should prefer the
flag. `runtime-push.sh` accepts the same `--ozone=…` flag for
symmetry. Tags published: `runtime-<hash>` (headless) and
`runtime-x11-<hash>` (x11), keyed on hashes of the patch + bridge
source set.

## Container-level deployment

The `roctinam/carbonyl-agent` repo's `docker/qa-runner/` is the
reference container for modes 2 and 3. It bundles:

- Xorg with `dummy` (CPU-only framebuffer) and `modesetting` (KMS/GPU)
  drivers, switched at entrypoint via `CARBONYL_GPU_MODE=auto|cpu|gpu`
- `scrot`, `ffmpeg`, `x11vnc` for visual capture
- python-uinput bindings for emitting trusted input events
- A non-root `agent` user wired to the host `input` group (use
  `--group-add input` and the provided udev rule on the host)

Set `CARBONYL_X_MIRROR=1` in the container `-e` env to opt into
mode 3.

---

## Validation

Both output pipelines are exercised end-to-end on every x11 release
build by `scripts/test-x-mirror.sh` (CI step in `build-runtime.yml`).
The test asserts:

- Terminal stream contains ≥50 quadrant block characters and 24-bit
  ANSI SGR escapes for the fixture's signature colours
- `scrot` of `$DISPLAY` shows pixel-histogram coverage of the same
  colours

If either side fails, the pipeline blocks before the runtime is rolled
out to dependent stages.

---

## References

- Implementation: `src/browser/x_mirror.{h,cc}`, `src/browser/host_display_client.cc`
- Decision: `roctinam/carbonyl#63` (Option A patch-depth analysis)
- ADR: `docs/adr-002-trusted-input-approach.md` rev 2
- Test: `scripts/test-x-mirror.sh`, `tests/fixtures/x-mirror.html`
- CI step: `.gitea/workflows/build-runtime.yml` (`Run dual-output validation`)
