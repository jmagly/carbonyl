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

        // Two paths: consumer-provided viewport vs legacy terminal-derived.
        //
        // Legacy path: `browser = cells * scale` where `scale = (2, 4) / dpi`
        // and `dpi` comes from terminal cell-metric gymnastics. Blink lays out
        // against a CSS viewport whose size depends on terminal cell count —
        // at small terminals that produces an absurdly wide CSS viewport
        // (see #37: a 220x50 terminal yields ~6926x4129 CSS viewport, pushing
        // the X login modal off-screen).
        //
        // Consumer-provided (`--viewport=WxH` or `CARBONYL_VIEWPORT=WxH`):
        // browser is fixed at the requested CSS size, `dpi = 1.0`. Chromium
        // lays out against exactly that viewport and rasters at the same size
        // in physical pixels. The terminal samples a `cells * (2, 4)` window
        // of that raster — if the terminal is large enough the whole page is
        // visible, otherwise the SDK can pan/stitch to cover the rest.
        if let Some((w, h)) = self.cmd.viewport {
            self.dpi = 1.0;
            self.scale = Size::new(2.0, 4.0);
            self.browser = Size::new(w, h);
        } else {
            let zoom = 1.5 * self.cmd.zoom;
            let auto_scale = false;
            let cell_pixels = if auto_scale {
                Size::new(cell.width as f32, cell.height as f32)
                    / self.cells.cast()
            } else {
                Size::new(8.0, 16.0)
            };
            // Normalize the cells dimensions for an aspect ratio of 1:2
            let cell_width = (cell_pixels.width + cell_pixels.height / 2.0) / 2.0;

            // Round DPI to 2 decimals for proper viewport computations
            self.dpi = (2.0 / cell_width * zoom * 100.0).ceil() / 100.0;
            // A virtual cell should contain a 2x4 pixel quadrant
            self.scale = Size::new(2.0, 4.0) / self.dpi;
            self.browser = self.cells.cast::<f32>().mul(self.scale).ceil().cast();
        }

        self
    }
}

fn parse_var<T: FromStr>(var: &str) -> Option<T> {
    std::env::var(var).ok()?.parse().ok()
}
