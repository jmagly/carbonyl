use core::mem::MaybeUninit;
use std::str::FromStr;

use crate::{cli::CommandLine, gfx::Size, utils::log};

/// A terminal window.
#[derive(Clone, Debug)]
pub struct Window {
    /// Device pixel ratio
    pub dpi: f32,
    /// Size of a terminal cell in pixels
    pub scale: Size<f32>,
    /// Size of the termina window in cells
    pub cells: Size,
    /// Size of the browser window in pixels
    pub browser: Size,
    /// Framebuffer device resolution in pixels, when `--framebuffer` opened a
    /// device (#125 cycle 2). When set (and no explicit `--viewport`), the CSS
    /// viewport tracks this so Blink lays out against the real panel.
    pub fb_size: Option<Size>,
    /// Command line arguments
    pub cmd: CommandLine,
}

impl Window {
    /// Read the window
    pub fn read() -> Window {
        let mut window = Self {
            dpi: 1.0,
            scale: (0.0, 0.0).into(),
            cells: (0, 0).into(),
            browser: (0, 0).into(),
            fb_size: None,
            cmd: CommandLine::parse(),
        };

        window.update();

        window
    }

    pub fn update(&mut self) -> &Self {
        let (mut term, mut cell) = unsafe {
            let mut ptr = MaybeUninit::<libc::winsize>::uninit();

            if libc::ioctl(libc::STDOUT_FILENO, libc::TIOCGWINSZ, ptr.as_mut_ptr()) == 0 {
                let size = ptr.assume_init();

                (
                    Size::new(size.ws_col, size.ws_row),
                    Size::new(size.ws_xpixel, size.ws_ypixel),
                )
            } else {
                (Size::splat(0), Size::splat(0))
            }
        };

        if cell.width == 0 || cell.height == 0 {
            cell.width = 8;
            cell.height = 16;
        }

        if term.width == 0 || term.height == 0 {
            let cols = match parse_var("COLUMNS").unwrap_or(0) {
                0 => 80,
                x => x,
            };
            let rows = match parse_var("LINES").unwrap_or(0) {
                0 => 24,
                x => x,
            };

            log::warning!(
                "TIOCGWINSZ returned an empty size ({}x{}), defaulting to {}x{}",
                term.width,
                term.height,
                cols,
                rows
            );

            term.width = cols;
            term.height = rows;
        }

        // Keep one row for the UI bar.
        self.cells = Size::new(term.width.max(1), term.height.max(2) - 1).cast();

        // Two paths: consumer-provided viewport vs terminal-derived.
        //
        // Consumer-provided (`--viewport=WxH` or `CARBONYL_VIEWPORT=WxH`):
        // browser is fixed at the requested CSS size, `dpi = 1.0`. Chromium
        // lays out against exactly that viewport and rasters at the same size
        // in physical pixels. The terminal samples a `cells * (2, 4)` window
        // of that raster — if the terminal is large enough the whole page is
        // visible, otherwise the SDK can pan/stitch to cover the rest.
        //
        // Terminal-derived (no `--viewport`): the CSS layout viewport equals
        // the sample window dimensions (`cells * (2, 4) / zoom`). This makes
        // "what Blink lays out against" and "what the terminal samples"
        // identical — a page with `margin: 0 auto` centers within the rendered
        // area, with no phantom-wider-viewport gutter (see #99 Gap 2). `dpi`
        // is fixed at 1.0; the per-cell sample factor is the `scale` field.
        //
        // The pre-#99 path computed `dpi` from cell-pixel gymnastics and
        // produced a CSS viewport substantially wider than the sample window
        // — for a 360-cell-wide terminal the layout viewport was ~1895 px
        // while the sample window was 720 px, so 60%+ of the laid-out width
        // was never sampled and centered content rendered offset by hundreds
        // of pixels. See issue #99 for the empirical evidence (dead-space
        // measurements across six URLs at PTY 360×100).
        //
        // `cmd.zoom` is preserved by dividing browser size by the zoom factor:
        // a larger zoom shrinks the CSS viewport so each CSS pixel maps to
        // more terminal pixels, making rendered content visually larger
        // within the same sample window.
        if let Some((w, h)) = self.cmd.viewport {
            self.dpi = 1.0;
            self.scale = Size::new(2.0, 4.0);
            self.browser = Size::new(w, h);
        } else {
            let zoom = self.cmd.zoom.max(0.01); // guard against divide-by-zero
            self.dpi = 1.0;
            self.scale = Size::new(2.0, 4.0);
            // #125 cycle 2 (framebuffer): when a framebuffer device is open and
            // no explicit `--viewport` was given, lay Blink out against the real
            // device resolution so the page fills the panel at native pixels.
            // The terminal renderer is unchanged — it keeps the (2, 4) half-block
            // sample factor and samples a window of the same raster (additive,
            // like the X-mirror). Without a framebuffer the CSS viewport is the
            // terminal sample window, exactly as before.
            //
            // Divide by zoom so a larger zoom -> smaller CSS viewport ->
            // bigger-looking rendered content, in both regimes.
            let base = match (self.cmd.framebuffer.is_some(), self.fb_size) {
                (true, Some(fb)) => fb.cast::<f32>(),
                _ => self.cells.cast::<f32>().mul(self.scale),
            };
            self.browser = (base / zoom).ceil().cast();
        }
        // Silence unused-variable warning on `cell`; the terminal cell-pixel
        // hint is no longer consulted now that we derive the CSS viewport
        // directly from the cell count and the half-block sample factor.
        let _ = cell;

        self
    }
}

fn parse_var<T: FromStr>(var: &str) -> Option<T> {
    std::env::var(var).ok()?.parse().ok()
}
