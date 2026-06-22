use std::ops::ControlFlow;

use crate::input::*;

#[derive(Default)]
pub struct Parser {
    events: Vec<Event>,
    sequence: Sequence,
}

#[derive(Default)]
enum Sequence {
    #[default]
    Char,
    Escape,
    Control,
    Mouse(Mouse),
    Keyboard(Keyboard),
    DeviceControl(DeviceControl),
    Utf8(Utf8),
}

#[derive(Clone, Debug)]
pub enum TerminalEvent {
    Name(String),
    TrueColorSupported,
}

#[derive(Clone, Debug)]
pub enum Event {
    KeyPress { key: Key },
    MouseUp { row: usize, col: usize, button: u32 },
    MouseDown { row: usize, col: usize, button: u32 },
    MouseMove { row: usize, col: usize },
    Scroll { delta: isize },
    Terminal(TerminalEvent),
    Exit,
}

pub type ParseControlFlow = ControlFlow<Option<Event>, Option<Event>>;

impl Parser {
    pub fn new() -> Parser {
        Self::default()
    }

    pub fn parse(&mut self, input: &[u8]) -> Vec<Event> {
        let mut sequence = std::mem::take(&mut self.sequence);

        macro_rules! emit {
            ($event:expr) => {{
                if let Some(event) = $event.into() {
                    self.events.push(event);
                }

                Sequence::Char
            }};
            ($event:expr; continue) => {{
                if let Some(event) = $event.into() {
                    self.events.push(event);
                }

                continue;
            }};
        }
        macro_rules! parse {
            ($parser:expr, $key:expr) => (
                match $parser.parse($key) {
                    ControlFlow::Break(None) => Sequence::Char,
                    ControlFlow::Break(Some(event)) => emit!(event),
                    ControlFlow::Continue(None) => continue,
                    ControlFlow::Continue(Some(event)) => emit!(event; continue),
                }
            );
        }

        for &key in input {
            sequence = match sequence {
                Sequence::Char => match key {
                    0x1b => Sequence::Escape,
                    0x03 => emit!(Event::Exit),
                    // UTF-8 leading byte: accumulate the multi-byte sequence so
                    // non-ASCII / composed input reaches the page intact.
                    key if key >= 0x80 => Sequence::Utf8(Utf8::new(key)),
                    key => emit!(Event::KeyPress { key: key.into() }),
                },
                Sequence::Escape => match key {
                    b'[' => Sequence::Control,
                    b'P' => Sequence::DeviceControl(DeviceControl::new()),
                    0x1b => emit!(Event::KeyPress { key: 0x1b.into() }; continue),
                    key => {
                        emit!(Event::KeyPress { key: 0x1b.into() });
                        emit!(Event::KeyPress { key: key.into() })
                    }
                },
                Sequence::Control => match key {
                    b'<' => Sequence::Mouse(Mouse::new()),
                    b'1' => Sequence::Keyboard(Keyboard::new()),
                    // CSI Z (back-tab, terminfo `kcbt`): the bare Shift+Tab xterm
                    // emits for reverse focus. Deliver Tab (0x09) with shift so
                    // Blink runs reverse traversal once the FFI carries the
                    // modifier mask (#237). The modifyOtherKeys `CSI 1;2 Z`
                    // variant (rare, non-default) is intentionally out of scope.
                    b'Z' => emit!(Event::KeyPress { key: Key::back_tab() }),
                    key => emit!(Keyboard::key(key, 0)),
                },
                Sequence::Mouse(ref mut mouse) => parse!(mouse, key),
                Sequence::Keyboard(ref mut keyboard) => parse!(keyboard, key),
                Sequence::DeviceControl(ref mut dcs) => parse!(dcs, key),
                Sequence::Utf8(ref mut utf8) => parse!(utf8, key),
            }
        }

        self.sequence = sequence;

        std::mem::take(&mut self.events)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key_codes(events: Vec<Event>) -> Vec<u32> {
        events
            .into_iter()
            .filter_map(|e| match e {
                Event::KeyPress { key } => Some(key.char),
                _ => None,
            })
            .collect()
    }

    /// (char, modifier-mask) pairs for each keypress, so tests can assert that
    /// modifiers survive parsing and reach the FFI boundary (#237).
    fn key_codes_with_mask(events: Vec<Event>) -> Vec<(u32, u32)> {
        events
            .into_iter()
            .filter_map(|e| match e {
                Event::KeyPress { key } => Some((key.char, key.modifiers.mask())),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn csi_z_is_shift_tab_back_tab() {
        // xterm sends a bare CSI Z (ESC [ Z) for Shift+Tab. It must decode to
        // Tab (0x09) carrying the shift modifier (mask bit0) so reverse focus
        // works once the FFI forwards modifiers (#237).
        let mut p = Parser::new();
        assert_eq!(key_codes_with_mask(p.parse(b"\x1b[Z")), vec![(0x09, 0b0001)]);
    }

    #[test]
    fn plain_tab_has_no_modifiers() {
        // A bare Tab byte is still an unmodified Tab — only CSI Z carries shift.
        let mut p = Parser::new();
        assert_eq!(key_codes_with_mask(p.parse(b"\x09")), vec![(0x09, 0)]);
    }

    #[test]
    fn ascii_is_one_keypress_per_byte() {
        let mut p = Parser::new();
        assert_eq!(key_codes(p.parse(b"ab")), vec![0x61, 0x62]);
    }

    #[test]
    fn two_byte_utf8_decodes_to_one_codepoint() {
        // Cyrillic 'д' (U+0434) = 0xD0 0xB4 (#178).
        let mut p = Parser::new();
        assert_eq!(key_codes(p.parse("д".as_bytes())), vec![0x0434]);
    }

    #[test]
    fn three_byte_utf8_decodes_to_one_codepoint() {
        // CJK '中' (U+4E2D) = 0xE4 0xB8 0xAD (#217).
        let mut p = Parser::new();
        assert_eq!(key_codes(p.parse("中".as_bytes())), vec![0x4E2D]);
    }

    #[test]
    fn utf8_accumulates_across_parse_calls() {
        // Bytes can arrive split across reads; the codepoint must still be whole.
        let mut p = Parser::new();
        let bytes = "д".as_bytes();
        assert!(key_codes(p.parse(&bytes[..1])).is_empty());
        assert_eq!(key_codes(p.parse(&bytes[1..])), vec![0x0434]);
    }
}
