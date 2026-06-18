use std::env;

use unicode_width::UnicodeWidthStr;

use crate::{
    gfx::{Color, Point, Size},
    input::Key,
    utils::log,
};

pub enum NavigationAction {
    Ignore,
    Forward,
    GoTo(String),
    GoBack(),
    GoForward(),
    Refresh(),
}

#[derive(Debug)]
pub struct NavigationElement {
    pub text: String,
    pub background: Color,
    pub foreground: Color,
}

pub struct Navigation {
    url: Option<String>,
    size: Size,
    cursor: Option<usize>,
    can_go_back: bool,
    can_go_forward: bool,
    chrome_rows: u32,
}

impl Default for Navigation {
    fn default() -> Self {
        Self::new()
    }
}

impl Navigation {
    pub fn new() -> Self {
        Self::with_chrome_rows(1)
    }

    pub fn with_chrome_rows(chrome_rows: u32) -> Self {
        Self {
            url: None,
            size: (0, 0).into(),
            cursor: None,
            can_go_back: false,
            can_go_forward: false,
            chrome_rows: chrome_rows.max(1),
        }
    }

    /// Number of terminal rows the chrome occupies (always >= 1).
    pub fn height(&self) -> u32 {
        self.chrome_rows
    }

    pub fn cursor(&self) -> Option<Point> {
        // Place the text cursor on the middle chrome row so it sits inside
        // the URL band when chrome_rows > 1.
        Some((11 + self.cursor? as i32, (self.chrome_rows as i32) / 2).into())
    }

    /// True when the URL bar holds the text cursor, i.e. keystrokes are being
    /// typed into the address field rather than forwarded to the page. Used by
    /// the renderer to gate local chrome shortcuts (e.g. invert-colors) so they
    /// don't fire mid-edit.
    pub fn is_url_editing(&self) -> bool {
        self.cursor.is_some()
    }

    /// The platform navigation modifier: Cmd (meta) on macOS, Alt elsewhere.
    /// Matches what the navigation chrome already uses for back/forward.
    fn modifier_key(key: &Key) -> bool {
        match env::consts::OS {
            "macos" => key.modifiers.meta,
            _ => key.modifiers.alt,
        }
    }

    /// Local chrome shortcut for issue #181: `modifier + Up` toggles color
    /// inversion. `0x11` is the Up arrow (see `Keyboard::key`). This combo is
    /// collision-free with page input because `key_press` forwards only
    /// `key.char` to Chromium and drops the modifier — so `modifier+Up` would
    /// otherwise send the exact same byte to the page as a bare Up. The renderer
    /// consumes it (does not forward) when the URL bar is not being edited.
    pub fn is_invert_shortcut(key: &Key) -> bool {
        Self::modifier_key(key) && key.char == 0x11
    }

    pub fn keypress(&mut self, key: &Key) -> NavigationAction {
        let modifier_key = Self::modifier_key(key);

        match self.cursor {
            None => match (modifier_key, key.char) {
                (true, 0x14) => NavigationAction::GoBack(),
                (true, 0x13) => NavigationAction::GoForward(),
                _ => NavigationAction::Forward,
            },
            Some(cursor) => {
                if let Some(url) = &mut self.url {
                    // TODO: Unicode
                    match key.char {
                        // Return
                        0x0d => return NavigationAction::GoTo(url.clone()),
                        // Up
                        0x11 => self.cursor = Some(0),
                        // Down
                        0x12 => self.cursor = Some(url.width()),
                        // Right
                        0x13 => self.cursor = Some((cursor + 1).min(url.width())),
                        // Left
                        0x14 => self.cursor = Some(if cursor > 0 { cursor - 1 } else { 0 }),
                        // Backspace
                        0x7f => {
                            if cursor > 0 {
                                url.remove(cursor - 1);

                                self.cursor = Some(cursor - 1);
                            }
                        }
                        key => {
                            url.insert(cursor, key as char);

                            self.cursor = Some((cursor + 1).min(url.width()))
                        }
                    }

                    NavigationAction::Ignore
                } else {
                    NavigationAction::Forward
                }
            }
        }
    }

    pub fn display_url(&self) -> &str {
        match &self.url {
            None => "about:blank",
            Some(url) => url,
        }
    }

    pub fn url_size(&self) -> usize {
        self.display_url().width()
    }

    pub fn mouse_up(&mut self, origin: Point) -> NavigationAction {
        if origin.y < 0 || (origin.y as u32) >= self.chrome_rows {
            self.cursor = None;

            NavigationAction::Forward
        } else {
            NavigationAction::Ignore
        }
    }
    pub fn mouse_down(&mut self, origin: Point) -> NavigationAction {
        if origin.y < 0 || (origin.y as u32) >= self.chrome_rows {
            self.cursor = None;

            return NavigationAction::Forward;
        }

        self.cursor = None;

        match origin.x {
            0..=2 => NavigationAction::GoBack(),
            3..=5 => NavigationAction::GoForward(),
            6..=8 => NavigationAction::Refresh(),
            11.. => {
                self.cursor = Some(self.url_size().min(origin.x as usize - 11));

                log::debug!("setting cursor to {:?}", self.cursor);

                NavigationAction::Ignore
            }
            _ => NavigationAction::Ignore,
        }
    }
    pub fn mouse_move(&mut self, _origin: Point) -> NavigationAction {
        NavigationAction::Forward
    }

    pub fn push(&mut self, url: &str, can_go_back: bool, can_go_forward: bool) {
        if match (self.cursor, &self.url) {
            (None, _) => false,
            (_, None) => true,
            (_, Some(current)) => current != url,
        } {
            self.cursor = Some(url.len())
        }

        self.url = Some(url.to_owned());
        self.can_go_back = can_go_back;
        self.can_go_forward = can_go_forward;
    }

    pub fn set_size(&mut self, size: Size) {
        self.size = size
    }

    pub fn render_btn(&self, icon: &str, enabled: bool) -> [NavigationElement; 3] {
        let background = Color::splat(255);
        let foreground = Color::splat(0);

        [
            NavigationElement {
                text: "[".to_owned(),
                background,
                foreground,
            },
            NavigationElement {
                text: icon.to_owned(),
                background,
                foreground: if enabled {
                    foreground
                } else {
                    Color::splat(200)
                },
            },
            NavigationElement {
                text: "]".to_owned(),
                background,
                foreground,
            },
        ]
    }

    pub fn render(&self, size: Size) -> Vec<(Point, NavigationElement)> {
        let ui_elements = 13;
        let space = if size.width >= ui_elements {
            (size.width - ui_elements) as usize
        } else {
            0
        };
        let url: String = self.display_url().chars().take(space).collect();
        let width = url.width();
        let padded = format!(" {}{} ", url, " ".repeat(space - width));
        let mut elements = Vec::new();

        let lists = [
            self.render_btn("\u{276e}", self.can_go_back),
            self.render_btn("\u{276f}", self.can_go_forward),
            self.render_btn("↻", true),
            self.render_btn(&padded, true),
        ];

        // Stack chrome across N rows. Each row renders the full button
        // strip so the URL bar reads at chrome_rows x cell height; at
        // chrome_rows=1 this matches the historical single-row layout
        // exactly. The renderer treats each emitted element as a 1-row
        // background-fill plus the text glyph at the same origin.
        for row in 0..(self.chrome_rows as i32) {
            let mut point = Point::new(0, row);

            for list in &lists {
                for element in list {
                    let elem_width = element.text.width() as i32;

                    elements.push((
                        point,
                        NavigationElement {
                            text: element.text.clone(),
                            background: element.background,
                            foreground: element.foreground,
                        },
                    ));

                    point = point + (elem_width, 0);
                }
            }
        }

        elements
    }
}

#[cfg(test)]
mod tests {
    use std::env;

    use super::Navigation;
    use crate::input::{Key, KeyModifiers};

    /// Build a Key carrying the current platform's navigation modifier
    /// (Cmd on macOS, Alt elsewhere) so the assertions hold on any host.
    fn key_with_modifier(char: u8) -> Key {
        let mut modifiers = KeyModifiers::default();
        match env::consts::OS {
            "macos" => modifiers.meta = true,
            _ => modifiers.alt = true,
        }
        Key { char, modifiers }
    }

    #[test]
    fn invert_shortcut_is_modifier_plus_up() {
        // 0x11 == Up
        assert!(Navigation::is_invert_shortcut(&key_with_modifier(0x11)));
    }

    #[test]
    fn invert_shortcut_requires_modifier() {
        let plain_up = Key {
            char: 0x11,
            modifiers: KeyModifiers::default(),
        };
        assert!(!Navigation::is_invert_shortcut(&plain_up));
    }

    #[test]
    fn invert_shortcut_requires_up_key() {
        // modifier + Down (0x12) is not the invert shortcut
        assert!(!Navigation::is_invert_shortcut(&key_with_modifier(0x12)));
        // modifier + Left (0x14, back) is not the invert shortcut
        assert!(!Navigation::is_invert_shortcut(&key_with_modifier(0x14)));
    }

    #[test]
    fn url_not_editing_by_default() {
        assert!(!Navigation::new().is_url_editing());
    }
}
