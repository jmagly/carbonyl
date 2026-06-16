# Framebuffer backend (`/dev/fb0`) — #125

Direct-to-Linux-framebuffer output so Carbonyl can render at full pixel
resolution on a local system TTY **without** an X11/Wayland session — kiosk,
appliance, recovery-console, and bare-metal setups. The existing terminal/ANSI
renderer (SSH-friendly) remains the default and is unchanged.

## Status

| Cycle | State |
|-------|-------|
| **1 (landed)** | Self-contained framebuffer backend module (`src/output/framebuffer.rs`): device open, `FBIOGET_{F,V}SCREENINFO` geometry, `mmap`, BGRA→native pixel conversion, stride-aware blit, explicit error taxonomy. Pure convert/blit/format logic is unit-tested (`cargo test --lib`). CLI flag `--framebuffer[=PATH]` + `CARBONYL_FRAMEBUFFER` parsed. Shipped in **v0.2.0-alpha.10**. |
| **2 — output sink + viewport (landed)** | The backend is wired into the live render path as an **additive output sink** modeled on the X-mirror (`CARBONYL_X_MIRROR`): the bridge opens the device in `carbonyl_renderer_create`, blits every BGRA raster to it from `carbonyl_renderer_draw_bitmap` **while the terminal renderer keeps running**, and on open failure logs the typed `FbError` and falls back to terminal-only. When `--framebuffer` is set and no explicit `--viewport` is given, the CSS viewport tracks the device resolution (`fb_var_screeninfo.{xres,yres}`) so Blink lays out against the real panel. Compile + unit-tested via `cargo`; end-to-end verified by the CI Chromium build. |
| **2 — input (remaining)** | Local-console input via **evdev** (`/dev/input/event*`), reusing the #58/#57 Trusted Automation evdev/uinput integration. Needed only for the no-PTY/kiosk case; when driven additively from a controlling terminal/SSH session the existing stdin path already carries input. Requires a real console + device to verify. |

## Enabling (once cycle 2 lands)

```bash
carbonyl --framebuffer https://example.com          # default device /dev/fb0
carbonyl --framebuffer=/dev/fb1 https://example.com # explicit device
CARBONYL_FRAMEBUFFER=/dev/fb0 carbonyl https://example.com
```

`--framebuffer` (or the env var) selects the framebuffer backend. An empty or
missing value defaults to `/dev/fb0`. Without the flag, Carbonyl uses the
terminal renderer exactly as before — the framebuffer path is strictly opt-in.

## How frames flow

Chromium hands the Rust bridge a **BGRA8888** raster (byte order B, G, R, A) via
the software output device. The bridge's `carbonyl_renderer_draw_bitmap`
(`src/browser/bridge.rs`) fans the raster out to every active output sink:

- the terminal renderer (`Renderer::draw_background`), which quantizes it into
  half-block cells, and
- the framebuffer sink (`Framebuffer::present`, when `--framebuffer` opened a
  device), which converts it to the device's native pixel format and blits it to
  the memory-mapped framebuffer at full resolution.

The framebuffer is **additive**, not a replacement: it coexists with the
terminal renderer exactly as the X-mirror (`CARBONYL_X_MIRROR`,
`src/browser/x_mirror.cc`) does. It is *not* an Ozone platform — Chromium stays
`ozone_platform = "headless"`; the framebuffer is one more output sink in the
bridge layer alongside the terminal quantizer and the X-mirror.

**Same-VT caveat:** if ANSI stdout and the framebuffer target the *same* physical
console, the terminal escape sequences will scribble over the framebuffer image.
Drive the framebuffer from a session whose stdout goes elsewhere (SSH, a
redirected log, or a different VT). A collision-driven stdout-quiet is a possible
future refinement, not baked-in exclusivity.

## Pixel format handling

The target format is read from the device's `fb_var_screeninfo` and applied with
a generic, bitfield-driven packer (no per-format special-casing):

- Each color channel (`red`/`green`/`blue`) carries an `offset` and `length`
  from the kernel. The 8-bit source sample is scaled to `length` bits
  (`sample >> (8 - length)`) and shifted to `offset`; the channels are OR-ed
  into the device word and stored little-endian as `bytes_per_pixel` bytes.
- This handles the common depths directly:
  - **32bpp** XRGB8888 / BGRX8888 (offsets 16/8/0 in either channel order).
  - **16bpp** RGB565 (R@11 len5, G@5 len6, B@0 len5).
- Other depths (e.g. 24bpp packed, 8bpp paletted) return
  `UnsupportedFormat { bits_per_pixel }` rather than rendering garbage.

Row **stride** comes from `fb_fix_screeninfo.line_length` (which may exceed
`xres * bytes_per_pixel` due to padding); the blit writes each row at its true
stride offset.

## Resolution handling

Device resolution is `fb_var_screeninfo.{xres, yres}`. In framebuffer mode the
browser viewport should be sized to match the device resolution (cycle-2
wiring), so Blink lays out against the real pixel dimensions of the console
rather than a terminal cell grid.

## Failure modes (explicit and actionable)

`Framebuffer::open` returns a typed error; each maps to an actionable message:

| Error | Cause | Operator action |
|-------|-------|-----------------|
| `NotFound(path)` | device node absent | use a console with `CONFIG_FB`, or drop `--framebuffer` |
| `PermissionDenied(path)` | not in `video` group / not root | `sudo usermod -aG video $USER` (re-login), or run on the console as root |
| `Busy(path)` | device already in use | stop the other framebuffer consumer |
| `Ioctl(err)` | `FBIOGET_*SCREENINFO` failed | device may not be a real framebuffer |
| `Mmap(err)` | `mmap` failed | check `smem_len` / kernel support |
| `UnsupportedFormat { bits_per_pixel }` | depth not 16/32bpp | reconfigure the console to a 16/32bpp mode |

## Cycle-2 input (remaining)

- **Input source — decided: evdev/uinput.** The no-PTY/kiosk case reads
  `/dev/input/event*` directly (keyboard + pointer), reusing the Trusted
  Automation evdev/uinput integration (#58/#57). The escape-sequence stdin parser
  is geared to terminal emulators, so it can't serve a bare VT; evdev is the
  right source there. When the framebuffer is driven additively *from* a
  controlling terminal/SSH session, the existing stdin path already carries
  input, so evdev is only required for the headless-console case. Pointer
  coordinates in framebuffer mode are device pixels (1:1), so the listen loop's
  coordinate scaling is device-aware rather than cell-scaled.
- **CI smoke.** Verify against a fake/loopback framebuffer (e.g. `vfb`/`fbtest`
  in a container) rather than a real host `/dev/fb0`; the pure convert/blit core
  is already unit-tested without a device.

## References

- Issue: roctinam/carbonyl#125
- Module: `src/output/framebuffer.rs`
- Frame source / integration seam: `src/output/renderer.rs` (`draw_background`),
  `src/browser/bridge.rs` (the `draw_background` call site)
- Kernel UAPI: `<linux/fb.h>` (`fb_var_screeninfo`, `fb_fix_screeninfo`,
  `FBIOGET_VSCREENINFO`/`FBIOGET_FSCREENINFO`)
