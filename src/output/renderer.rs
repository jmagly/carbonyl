use std::{
    borrow::Cow,
    io::{self, Write},
    rc::Rc,
};

use unicode_bidi::BidiInfo;
use unicode_segmentation::UnicodeSegmentation;
use unicode_width::UnicodeWidthStr;

use crate::{
    gfx::{Color, Point, Rect, Size},
    input::Key,
    ui::navigation::{Navigation, NavigationAction},
    utils::log,
};

use super::{Cell, Grapheme, Painter};

pub struct Renderer {
    nav: Navigation,
    cells: Vec<(Cell, Cell)>,
    painter: Painter,
    size: Size,
    /// Set when a state change that isn't reflected in the cell buffer (e.g. the
    /// invert-colors toggle, issue #181) requires every cell to be re-emitted on
    /// the next `render`, bypassing the usual previous/current diff.
    force_repaint: bool,
}

impl Default for Renderer {
    fn default() -> Self {
        Self::new()
    }
}

impl Renderer {
    pub fn new() -> Renderer {
        Self::with_chrome_rows(1)
    }

    pub fn with_chrome_rows(chrome_rows: u32) -> Renderer {
        Renderer {
            nav: Navigation::with_chrome_rows(chrome_rows),
            cells: Vec::with_capacity(0),
            painter: Painter::new(),
            size: Size::new(0, 0),
            force_repaint: false,
        }
    }

    pub fn enable_true_color(&mut self) {
        self.painter.set_true_color(true)
    }

    pub fn keypress(&mut self, key: &Key) -> io::Result<NavigationAction> {
        // Local chrome shortcut (issue #181): modifier + Up toggles color
        // inversion. Consumed here (never forwarded to Chromium) and only when
        // the URL bar isn't being edited, so Up still moves the text cursor.
        if !self.nav.is_url_editing() && Navigation::is_invert_shortcut(key) {
            self.painter.toggle_invert();
            self.force_repaint = true;

            return Ok(NavigationAction::Ignore);
        }

        let action = self.nav.keypress(key);

        Ok(action)
    }
    pub fn mouse_up(&mut self, origin: Point) -> io::Result<NavigationAction> {
        let action = self.nav.mouse_up(origin);

        Ok(action)
    }
    pub fn mouse_down(&mut self, origin: Point) -> io::Result<NavigationAction> {
        let action = self.nav.mouse_down(origin);

        Ok(action)
    }
    pub fn mouse_move(&mut self, origin: Point) -> io::Result<NavigationAction> {
        let action = self.nav.mouse_move(origin);

        Ok(action)
    }

    pub fn push_nav(&mut self, url: &str, can_go_back: bool, can_go_forward: bool) {
        self.nav.push(url, can_go_back, can_go_forward)
    }

    pub fn get_size(&self) -> Size {
        self.size
    }

    pub fn set_size(&mut self, size: Size) {
        self.nav.set_size(size);
        self.size = size;

        let mut x = 0;
        let mut y = 0;
        let bound = size.width - 1;
        let cells = (size.width + size.width * size.height) as usize;

        self.cells.clear();
        self.cells.resize_with(cells, || {
            let cell = (Cell::new(x, y), Cell::new(x, y));

            if x < bound {
                x += 1;
            } else {
                x = 0;
                y += 1;
            }

            cell
        });
    }

    pub fn render(&mut self) -> io::Result<()> {
        let size = self.size;

        for (origin, element) in self.nav.render(size) {
            self.fill_rect(
                Rect::new(origin.x, origin.y, element.text.width() as u32, 1),
                element.background,
            );
            self.draw_text(
                &element.text,
                origin * (2, 1),
                Size::splat(0),
                element.foreground,
            );
        }

        self.painter.begin()?;

        // After an invert toggle the cell buffer is unchanged but the emitted
        // colors must change, so repaint every cell once (issue #181).
        let force = std::mem::take(&mut self.force_repaint);

        for (previous, current) in self.cells.iter_mut() {
            if !force && current == previous {
                continue;
            }

            previous.quadrant = current.quadrant;
            previous.grapheme = current.grapheme.clone();

            self.painter.paint(current)?;
        }

        self.painter.end(self.nav.cursor())?;

        Ok(())
    }

    /// Draw the background from a pixel array encoded in RGBA8888.
    ///
    /// Quadrant-rendering invariant: each terminal cell displays four sub-pixels
    /// sampled from a fixed 2x4 block of source pixels. The inner loop is
    /// clamped to `viewport = cells`, so it reads up to `cells * (2, 4)` source
    /// pixels starting at the damage rect origin. If the Chromium-side raster
    /// is larger than the sampled region, the terminal displays the upper-left
    /// `cells * (2, 4)` window of it (and the rest is invisible — #37). Set
    /// `--viewport=WxH` to the size you want Blink to lay out against.
    pub fn draw_background(&mut self, pixels: &[u8], pixels_size: Size, rect: Rect) {
        let viewport = self.size.cast::<usize>();

        if pixels.len() < viewport.width * viewport.height * 8 * 4 {
            log::debug!(
                "unexpected size, actual: {}, expected: {}",
                pixels.len(),
                viewport.width * viewport.height * 8 * 4
            );
            return;
        }

        // Convert the damage rect from source pixels to cell coordinates: one cell
        // corresponds to exactly 2 source pixels wide and 4 tall.
        let origin = rect.origin.cast::<f32>().max(0.0) / (2.0, 4.0);
        let size = rect.size.cast::<f32>().max(0.0) / (2.0, 4.0);
        let top = (origin.y.floor() as usize).min(viewport.height);
        let left = (origin.x.floor() as usize).min(viewport.width);
        let right = ((origin.x + size.width).ceil() as usize)
            .min(viewport.width)
            .max(left);
        let bottom = ((origin.y + size.height).ceil() as usize)
            .min(viewport.height)
            .max(top);
        let row_length = pixels_size.width as usize;
        let pixel = |x: usize, y: usize| {
            let base = (x + y * row_length) * 4;
            Color::new(pixels[base + 2], pixels[base + 1], pixels[base])
        };
        let pair = |x, y| pixel(x, y).avg_with(pixel(x, y + 1));

        for y in top..bottom {
            let index = (y + 1) * viewport.width;
            let start = index + left;
            let end = index + right;
            let (mut x, y) = (left * 2, y * 4);

            for (_, cell) in &mut self.cells[start..end] {
                cell.quadrant = (
                    pair(x + 0, y + 0),
                    pair(x + 1, y + 0),
                    pair(x + 1, y + 2),
                    pair(x + 0, y + 2),
                );

                x += 2;
            }
        }
    }

    pub fn clear_text(&mut self) {
        for (_, cell) in self.cells.iter_mut() {
            cell.grapheme = None
        }
    }

    pub fn set_title(&self, title: &str) -> io::Result<()> {
        let mut stdout = io::stdout();

        write!(stdout, "\x1b]0;{title}\x07")?;
        write!(stdout, "\x1b]1;{title}\x07")?;
        write!(stdout, "\x1b]2;{title}\x07")?;

        stdout.flush()
    }

    pub fn fill_rect(&mut self, rect: Rect, color: Color) {
        self.draw(rect, |cell| {
            cell.grapheme = None;
            cell.quadrant = (color, color, color, color);
        })
    }

    pub fn draw<F>(&mut self, bounds: Rect, mut draw: F)
    where
        F: FnMut(&mut Cell),
    {
        let origin = bounds.origin.cast::<usize>();
        let size = bounds.size.cast::<usize>();
        let viewport_width = self.size.width as usize;
        let top = origin.y;
        let bottom = top + size.height;

        // Iterate over each row
        for y in top..bottom {
            let left = y * viewport_width + origin.x;
            let right = left + size.width;

            for (_, current) in self.cells[left..right].iter_mut() {
                draw(current)
            }
        }
    }

    /// Render some text into the terminal output
    pub fn draw_text(&mut self, string: &str, origin: Point, size: Size, color: Color) {
        // Get an iterator starting at the text origin
        let len = self.cells.len();
        let viewport = &self.size.cast::<usize>();

        if size.width > 2 && size.height > 2 {
            let origin = (origin.cast::<f32>() / (2.0, 4.0) + (0.0, 1.0)).round();
            let size = (size.cast::<f32>() / (2.0, 4.0)).round();
            let left = (origin.x.max(0.0) as usize).min(viewport.width);
            let right = ((origin.x + size.width).max(0.0) as usize).min(viewport.width);
            let top = (origin.y.max(0.0) as usize).min(viewport.height);
            let bottom = ((origin.y + size.height).max(0.0) as usize).min(viewport.height);

            for y in top..bottom {
                let index = y * viewport.width;
                let start = index + left;
                let end = index + right;

                for (_, cell) in self.cells[start..end].iter_mut() {
                    cell.grapheme = None
                }
            }
        } else {
            // Compute the buffer index based on the position
            let index = origin.x / 2 + (origin.y + 1) / 4 * (viewport.width as i32);
            if index < 0 || viewport.width == 0 {
                return;
            }

            let mut cursor = len.min(index as usize);
            let row_end = len.min((cursor / viewport.width + 1) * viewport.width);

            let visual_text = visual_order(string);

            // Get every Unicode grapheme in the input string
            for grapheme in UnicodeSegmentation::graphemes(visual_text.as_ref(), true) {
                let width = grapheme.width();
                if width == 0 {
                    continue;
                }

                if cursor + width > row_end {
                    return;
                }

                for index in 0..width {
                    let (_, cell) = &mut self.cells[cursor + index];
                    let next = Grapheme {
                        // Create a new shared reference to the text
                        color,
                        index,
                        width,
                        // Export the set of unicode code points for this graphene into an UTF-8 string
                        char: grapheme.to_string(),
                    };

                    if match cell.grapheme {
                        None => true,
                        Some(ref previous) => {
                            previous.color != next.color || previous.char != next.char
                        }
                    } {
                        cell.grapheme = Some(Rc::new(next))
                    }
                }

                cursor += width;
            }
        }
    }
}

fn visual_order(text: &str) -> Cow<'_, str> {
    let bidi = BidiInfo::new(text, None);
    let Some(paragraph) = bidi.paragraphs.first() else {
        return Cow::Borrowed(text);
    };
    let reordered = bidi.reorder_line(paragraph, paragraph.range.clone());

    if reordered == text {
        Cow::Borrowed(text)
    } else {
        Cow::Owned(reordered.into_owned())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text_at(renderer: &Renderer, row: usize, col: usize) -> Option<&str> {
        renderer.cells[row * renderer.size.width as usize + col]
            .1
            .grapheme
            .as_ref()
            .map(|grapheme| grapheme.char.as_str())
    }

    #[test]
    fn wide_grapheme_at_right_edge_does_not_bleed_to_next_row() {
        let mut renderer = Renderer::new();
        renderer.set_size(Size::new(4, 4));

        // Cell row 1, col 3: a width-2 CJK grapheme does not fit on this row.
        renderer.draw_text("界", Point::new(6, 3), Size::splat(0), Color::splat(255));

        assert_eq!(text_at(&renderer, 1, 3), None);
        assert_eq!(text_at(&renderer, 2, 0), None);
    }

    #[test]
    fn wide_grapheme_fits_when_two_cells_remain() {
        let mut renderer = Renderer::new();
        renderer.set_size(Size::new(4, 4));

        renderer.draw_text("界", Point::new(4, 3), Size::splat(0), Color::splat(255));

        assert_eq!(text_at(&renderer, 1, 2), Some("界"));
        assert_eq!(text_at(&renderer, 1, 3), Some("界"));
        assert_eq!(text_at(&renderer, 2, 0), None);
    }

    #[test]
    fn pure_rtl_text_is_drawn_in_visual_order() {
        let mut renderer = Renderer::new();
        renderer.set_size(Size::new(8, 4));

        renderer.draw_text("אבג", Point::new(0, 3), Size::splat(0), Color::splat(255));

        assert_eq!(text_at(&renderer, 1, 0), Some("ג"));
        assert_eq!(text_at(&renderer, 1, 1), Some("ב"));
        assert_eq!(text_at(&renderer, 1, 2), Some("א"));
    }

    #[test]
    fn ltr_text_stays_in_logical_order() {
        let mut renderer = Renderer::new();
        renderer.set_size(Size::new(8, 4));

        renderer.draw_text("abc", Point::new(0, 3), Size::splat(0), Color::splat(255));

        assert_eq!(text_at(&renderer, 1, 0), Some("a"));
        assert_eq!(text_at(&renderer, 1, 1), Some("b"));
        assert_eq!(text_at(&renderer, 1, 2), Some("c"));
    }
}
