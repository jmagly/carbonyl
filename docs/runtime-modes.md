# Carbonyl runtime modes

Carbonyl ships one binary that supports multiple deployment modes. The mode
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
| Experimental human operator window | **Views/Aura operator spike** | native X11 keyboard/pointer | the hosted native window plus terminal | full |
| Text-only extraction (scraping, LLM pipes) | **`--dump-text`** | none — single-shot navigation | none — bypasses renderer | full |
| Visual frame dump (screenshots, mailcap filters) | **`--dump`** | none — single-shot navigation | none — bypasses terminal renderer | full compositor frame |
| Terminal image protocols | **`--sixel[=auto]`**, **`--terminal-image=<mode>`**, or **`--dump=<mode>`** | terminal with matching image support | matching terminal emulator | full compositor frame |

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

In a container — see `docker/` patterns in `jmagly/carbonyl-agent`:

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

The mirror window uses a **fixed compositor-raster policy**. Resizing the X
window does not change the CSS viewport or terminal geometry: the current
raster is centered and either clipped or letterboxed. Expose, cover/uncover,
minimize/restore, and resize events repaint from a retained complete frame, so
the window manager and compositor do not fight over window size. Closing the X
window disables only the mirror; the browser and terminal session continue.

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

## Experimental Views/Aura operator host

The #285 spike can host the active page in a real Carbonyl-owned Views/Aura
window while the terminal renderer consumes the same software compositor
frames:

```bash
DISPLAY=:99 carbonyl \
  --ozone-platform=x11 \
  --carbonyl-operator-window \
  --viewport=1280x720 \
  https://example.com
```

Issue #286 also provides a separately built, X11-only experimental launcher.
It injects the operator switch and replaces itself with the sibling
`headless_shell` in the same process. The normal shell target and packaged
`carbonyl` binary remain unchanged:

```bash
autoninja -C out/Default-x11 \
  carbonyl/src/browser:carbonyl_operator_shell

DISPLAY=:99 out/Default-x11/carbonyl_operator_shell \
  --user-data-dir=/var/lib/carbonyl/operator-profile \
  https://example.com
```

Run the dual-output/input smoke directly against that target with:

```bash
DISPLAY=:99 \
CARBONYL_OPERATOR_SHELL_BIN=out/Default-x11/carbonyl_operator_shell \
scripts/test-operator-window.sh
```

This requires an X11 runtime; a headless-only build rejects the switch with an
explicit diagnostic. The switch is off by default and does not disable
sandboxing or site isolation.

### Geometry, focus, and input contract

Operator mode has one geometry path. The native `views::Widget` client bounds
size a vertical Views layout whose flexible `views::WebView` continuously
resizes the already hosted `WebContents`. Aura/Ozone applies device scale and
translates native coordinates into content coordinates. The terminal
rows/columns remain a separate presentation of the same compositor damage and
never resize the native page. There is no raw-Xlib input-forwarding path.

The window uses normal window-manager decorations and size controls. Native
activation restores the page's last focused view; deactivation stores it.
Minimize/restore therefore preserves focus without injecting a synthetic DOM
event. Closing the operator window requests orderly browser shutdown instead
of leaving an invisible process running. Native input enters through Aura's
normal event dispatcher; there is no Carbonyl event-forging path. The smoke
activates the operator window and uses untargeted `xdotool` key and pointer
commands, which take xdotool's XTEST path. It deliberately avoids `--window`
for input because targeted xdotool input uses synthetic XSendEvent delivery.
Kernel uinput remains a separate isolated-worker graduation check.

The operator browser process intentionally omits Chromium's internal
`--headless` marker. Chromium otherwise installs its mock input method, which
forwards key events but cannot commit XKB/IME text. Renderer and utility child
processes retain their normal headless marker, and the GPU child uses the X11
UI message pump required by this explicit mode.

### Carbonyl-owned browser controls

Operator mode places native Carbonyl controls above the page-owned WebView.
The first row provides Back, Forward, Reload/Stop, and an address/search field;
the second row displays the committed origin and a conservative security
classification. Because both rows are separate Views children rather than a
page overlay, page content cannot paint over or supply text shown in the
browser-owned display area.

The security line never uses a page title or page-provided string. It derives
only from the last committed `NavigationEntry`, its actual URL, page type, SSL
status, certificate flags, and mixed-content flags. Labels distinguish Secure,
Not secure, Local, Local file, Certificate error, Internal, and Error page.
HTTPS is labeled Secure only after SSL state is initialized and no certificate
or insecure-content signal is present.

Address entry accepts Unicode and uses Chromium's user-typed URL fixer only for
explicitly allowed `http`, `https`, `file`, `about`, and `chrome` destinations.
Domain-, localhost-, and IP-shaped input navigates directly. Other text is
escaped into a DuckDuckGo HTTPS query; schemes such as `javascript` are treated
as search text rather than executed. Enter submits, Escape cancels, and native
Textfield behavior supplies selection, copy, and paste.

Native operator shortcuts are:

- `Ctrl+L`: focus and select the address field
- `Alt+Left` / `Alt+Right`: history back / forward
- `Ctrl+R` or `F5`: activate Reload/Stop

They are registered at the high-priority Views accelerator tier specifically
so a consumed browser command is not also delivered to page script. These
shortcuts apply only while the native operator widget has focus. Terminal-mode
navigation and inspection bindings remain on the PTY path and are unchanged.

`scripts/test-operator-controls.sh` exercises these controls only when
`CARBONYL_UI_TEST_GUEST=1` is explicitly set inside the disposable Ubuntu
26.04 UI-test VM. It uses that guest's local Xorg display; it must not be aimed
at a developer workstation display or Wayland compatibility socket.

Shutdown destroys the shell-owned `OperatorWindow` before
`HeadlessBrowserImpl::Shutdown()` clears BrowserContexts and WebContents. The
widget observer also holds a `WebContents::GetWeakPtr()` handle so queued native
activation notifications cannot outlive the page during the shutdown drain.

The regression harnesses independently assert native resize, post-resize
terminal progress, primary and context-menu clicks, wheel and keyboard input,
stored-focus recovery across a real WM minimize/restore, browser-owned
history/reload/stop/address behavior, redirect and error-page state, shortcut
isolation, native pixels, and close-triggered process exit. Composed
Unicode/IME, monitor-scale changes, and kernel uinput remain isolated-worker
graduation checks: support depends on the guest XKB/IME and window-manager
configuration and is not claimed from an Xvfb-only run.

This is an architecture prototype, not yet the production operator mode. In
particular, do not open a user-data directory concurrently in operator and
headless processes. Orderly storage-flush acknowledgement (#292), the external
profile lease (agent #136), the remaining isolated geometry/input matrix
(#287), and the
round-trip/crash QA matrix (QA #37) remain graduation gates. See
[ADR-006](adr-006-native-operator-host.md).

---

## Mode 4 — `--dump-text` (text-only extraction, no renderer)

`--dump-text` skips the terminal renderer entirely. Carbonyl boots
chromium, navigates to the URL, waits for load + an idle window, then
emits the page's text on stdout and exits. No half-block sampling, no
ANSI, no terminal control sequences in the output.

```bash
carbonyl --dump-text https://example.com
carbonyl --dump-text=accessibility --idle=2000 https://example.com
carbonyl --dump-text=raw-dom --max-wait=10000 https://example.com
```

**Modes:**

| Mode | Source | Use case |
|---|---|---|
| `innertext` (default) | `document.body.innerText` | Visual order; paragraphs, list items, table rows |
| `accessibility` | Browser-process AX snapshot, serialized to JSON | Semantic structure; headings, landmarks, roles |
| `raw-dom` | `document.documentElement.outerHTML` | No transformation; full HTML |

`accessibility` mode does not eval JavaScript. It calls the browser-process
accessibility-tree snapshot (the FFI from #4, `AccessibilityHandler`) and
emits the role/name/value/landmark JSON tree on stdout. On any failure path
(AX mode off, no bound WebContents) it emits the sentinel `{"error":"no_tree"}`.

**Timing flags:**

- `--idle=<ms>` — wait this long after the load event before extracting (default: 500). Set higher for SPA hydration.
- `--max-wait=<ms>` — hard timeout (default: 30000).

**Why not just use `--ozone-platform=x11` and grab the page through DevTools?**

Two reasons. First, this mode is *single-shot*: one URL in, one text blob
out, exit. No long-lived browser, no driver, no `$DISPLAY`. Second, the
implementation does not raster anything — no compositor frames, no Skia,
no terminal output stream. The renderer-side hook reads the text out of
Blink directly, which means downstream callers don't pay for visual
rendering they're only going to post-process back into text.

**Implementation notes:**

The renderer-side extraction lives on the carbonyl renderer process
(where Blink runs), reached from the browser process via the existing
Mojo channel defined in `chromium/src/carbonyl/src/browser/`. The
browser process triggers extraction after the load + idle window, the
renderer reads `Document::body().innerText()` (or the accessibility
tree / outerHTML per mode), and the result returns over Mojo for the
browser to emit on stdout. See #88 for the integration plan and #4 / #5
for the dependent Blink-facing FFI work.

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0`  | Load succeeded; text emitted on stdout |
| `3`  | WebContents destroyed before extraction completed (renderer crash) |
| `4`  | Primary frame host unavailable when the idle timer elapsed |
| `5`  | `--max-wait` elapsed; page never reached the load-complete state |
| `6`  | Navigation failed (DNS, connection refused, TLS error, etc.) — chromium would have served its error page; instead exit 6 is returned and stdout stays empty (#91) |

A useful caller pattern is to check both the exit code and the stdout
length, since a real page can legitimately have an empty `innerText`.

---

## Mode 5 — `--dump` / `--screenshot` (frame dump, no terminal renderer)

`--dump[=png|sixel|kitty|iterm2]` loads the URL, watches compositor frames,
waits until the frame has stopped changing for the idle window, writes the
current frame to stdout, and exits. The terminal renderer is not started, so
stdout contains only the selected payload.

```bash
carbonyl --dump --viewport=1280x800 https://example.com > page.png
carbonyl --screenshot=png --page-height=4000 https://example.com > full-page.png
carbonyl --dump=sixel --viewport=1280x800 https://example.com > page.sixel
carbonyl --dump=kitty --viewport=1280x800 https://example.com > page.kitty
carbonyl --dump=iterm2 --viewport=1280x800 https://example.com > page.iterm2
```

The mode uses the same BGRA frame cache as the screenshot FFI, but it is
CLI-first and single-shot. `png` uses the PNG encoder; `sixel` uses the in-tree
sixel encoder for terminal image consumers. `kitty` and `iterm2` wrap the same
PNG frame in the respective terminal image protocol escape sequence. It is
intentionally separate from `--dump-text=raw-dom`: raw DOM returns
post-JavaScript HTML, while `--dump` returns the visual compositor frame.

For size/perf characterization, add `--debug` and redirect stderr separately.
Stdout remains the selected image payload; debug logs report the source raster
size and encoded byte count. For sixel, the log also includes palette size and
whether the exact palette or RGB332 fallback was used.

```bash
carbonyl --debug --dump=sixel --viewport=1280x800 https://example.com \
  > page.sixel 2> page.sixel.log
carbonyl --debug --dump=kitty --viewport=1280x800 https://example.com \
  > page.kitty 2> page.kitty.log
```

**Timing flags:**

- `--idle=<ms>` — wait this long after the latest compositor frame before
  writing the PNG (default: 500).
- `--max-wait=<ms>` — hard timeout waiting for a frame / idle window
  (default: 30000).

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0`  | frame written to stdout |
| `1`  | internal write/bridge failure |
| `6`  | no encodable frame arrived before `--max-wait` |

## Mode 6 — live terminal image output

`--sixel` is an explicit opt-in backend for terminals that support DEC sixel.
It keeps the terminal setup/input path, but disables the default Unicode
quadrant renderer for the session and writes each compositor frame as a sixel
image in the alt screen. `--terminal-image=kitty` and
`--terminal-image=iterm2` use the same live frame path but wrap each PNG frame
in the corresponding terminal image protocol.

```bash
carbonyl --sixel --viewport=1280x800 https://example.com
carbonyl --sixel=auto --viewport=1280x800 https://example.com
carbonyl --terminal-image=auto --viewport=1280x800 https://example.com
carbonyl --terminal-image=kitty --viewport=1280x800 https://example.com
carbonyl --terminal-image=iterm2 --viewport=1280x800 https://example.com
CARBONYL_SIXEL=1 carbonyl --viewport=1280x800 https://example.com
CARBONYL_SIXEL=auto carbonyl --viewport=1280x800 https://example.com
CARBONYL_TERMINAL_IMAGE=auto carbonyl --viewport=1280x800 https://example.com
CARBONYL_TERMINAL_IMAGE=kitty carbonyl --viewport=1280x800 https://example.com
```

Plain `--sixel` / `CARBONYL_SIXEL=1` is force-on mode for a known
sixel-capable terminal; otherwise the raw DCS payload may be visible.
`--sixel=auto` / `CARBONYL_SIXEL=auto` is conservative: Carbonyl sends a
Primary Device Attributes query during terminal setup, keeps the default
quadrant renderer active, and only routes subsequent frames to sixel after the
terminal reports DA1 attribute `4`. If no support report arrives, the normal
renderer remains the fallback.

`--terminal-image=auto` / `CARBONYL_TERMINAL_IMAGE=auto` is the broader
terminal-image detector. It selects kitty graphics when `KITTY_WINDOW_ID` is
present or `TERM=kitty`, selects iTerm2 inline images when `ITERM_SESSION_ID`
is present or `TERM_PROGRAM=iTerm.app`, and otherwise falls back to the
DA1-gated sixel policy above. Detection is intentionally conservative and
environment-based for kitty/iTerm2; explicit `--terminal-image=kitty` or
`--terminal-image=iterm2` remains available for compatible terminals such as
WezTerm.

---

## CLI options reference

```
carbonyl [options] [url]

  -f, --fps=<fps>            max frames per second the painter emits (default 60)
  -z, --zoom=<zoom>          CSS zoom percentage (default 100)
  --viewport=<WIDTHxHEIGHT>  override the CSS viewport Chromium lays out
                             against. Also via CARBONYL_VIEWPORT.
  -b, --bitmap               render text as quadrant bitmaps (default)
  --sixel[=on|auto|off]      render live frames as sixel terminal images
  --terminal-image=<mode>    render live frames with sixel, kitty, or iterm2
  --chrome-rows=<N>          stack the URL/chrome bar across N terminal rows
                             (default 1)
  --dump[=png|sixel|kitty|iterm2],
  --screenshot[=png|sixel|kitty|iterm2]
                             dump the current compositor frame
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

**Platforms.** Runtimes are published per platform triple:
`x86_64-unknown-linux-gnu` (Linux) and `aarch64-apple-darwin` (macOS,
Apple Silicon). `runtime-pull.sh` resolves the host triple automatically
(override with explicit `cpu`/`platform` args). The macOS arm64 runtime is
built on the `mutsu` host over SSH rather than a Gitea runner — see
[ci-runner-mutsu.md](ci-runner-mutsu.md).

## Cutting a release

Pushing a `v*` tag fires `.gitea/workflows/release.yml`, which
publishes both ozone variants by default. Each variant ships as its
own asset on the same Gitea + GitHub release:

| Variant | Asset filename |
|---|---|
| Headless | `carbonyl-<version>-<triple>.tgz` (+ `.sha256`) |
| x11 | `carbonyl-<version>-x11-<triple>.tgz` (+ `.sha256`) |
| macOS Apple Silicon | `carbonyl-<version>-aarch64-apple-darwin.tgz` (+ `.sha256`) |

The workflow is idempotent — re-running on an existing tag refreshes
assets without duplicating release entries. To publish only one
variant, dispatch `release.yml` manually with
`ozone_platform=headless` or `ozone_platform=x11`. macOS staging is
controlled separately by `include_macos` and defaults to `true`.

Hard guard: `release.yml` never rebuilds Chromium. It requires that
both `runtime-<hash>` and `runtime-x11-<hash>` Gitea releases already
exist for the tagged commit (built by `build-runtime.yml`). When
`include_macos=true`, it also requires
`runtime-<hash>/aarch64-apple-darwin.tgz`, produced by the mutsu SSH
driver. Missing inputs fail the release with an actionable error.

## Container-level deployment

The `jmagly/carbonyl-agent` repo's `docker/qa-runner/` is the
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

The terminal side is captured through `script` so Chromium/Carbonyl sees a real
PTY. Redirecting stdout to a regular file can produce a false failure because
the terminal renderer changes behavior when no tty is present.

If either side fails, the pipeline blocks before the runtime is rolled
out to dependent stages.

---

## References

- Implementation: `src/browser/x_mirror.{h,cc}`, `src/browser/host_display_client.cc`
- Decision: `jmagly/carbonyl#63` (Option A patch-depth analysis)
- ADR: `docs/adr-002-trusted-input-approach.md` rev 2
- Test: `scripts/test-x-mirror.sh`, `tests/fixtures/x-mirror.html`
- CI step: `.gitea/workflows/build-runtime.yml` (`Run dual-output validation`)
