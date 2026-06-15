# Framebuffer backend (`/dev/fb0`) — #125

Direct-to-Linux-framebuffer output so Carbonyl can render at full pixel
resolution on a local system TTY **without** an X11/Wayland session — kiosk,
appliance, recovery-console, and bare-metal setups. The existing terminal/ANSI
renderer (SSH-friendly) remains the default and is unchanged.

## Status

| Cycle | State |
|-------|-------|
| **1 (landed)** | Self-contained framebuffer backend module (`src/output/framebuffer.rs`): device open, `FBIOGET_{F,V}SCREENINFO` geometry, `mmap`, BGRA→native pixel conversion, stride-aware blit, explicit error taxonomy. Pure convert/blit/format logic is unit-tested (`cargo test --lib`). CLI flag `--framebuffer[=PATH]` + `CARBONYL_FRAMEBUFFER` is parsed; when set, startup prints a notice that the backend is **not yet active in this build** and falls back to the terminal renderer. |
| **2 (planned)** | Wire the backend into the live render path; derive the browser viewport from device geometry; input pairing. Requires the full Chromium build + a real console to verify end to end. |

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
the software output device. Today the bridge calls `Renderer::draw_background`
(`src/browser/bridge.rs`, the `renderer.draw_background(...)` call site), which
quantizes the raster into terminal half-block cells. In framebuffer mode the
same raster is instead converted to the device's native pixel format and blitted
to the memory-mapped framebuffer — no terminal quantization, full resolution.

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

## Open questions (for cycle 2)

- **Input pairing.** With no PTY in framebuffer mode, keyboard/mouse input needs
  a source: the controlling TTY (raw keyboard), the existing trusted-input path,
  or a separate evdev/uinput integration. Decision deferred — see #125 and the
  Trusted Automation work (#58/#57) for the evdev/uinput precedent.
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
