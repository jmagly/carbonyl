use crate::control_flow;

use super::{Event, Key, KeyModifiers, ParseControlFlow};

/// Accumulates a multi-byte UTF-8 sequence whose leading byte was seen in the
/// `Char` state, then emits a single `KeyPress` carrying the full Unicode
/// scalar value.
///
/// Terminals (and their input methods) deliver composed / non-ASCII text as
/// UTF-8 bytes on stdin. Without accumulation each byte became its own broken
/// single-byte `KeyPress`, so Cyrillic, CJK, etc. never reached the page as
/// the intended character (#178, #217).
#[derive(Clone, Debug)]
pub struct Utf8 {
    buf: Vec<u8>,
    need: usize,
}

impl Utf8 {
    /// `first` is the UTF-8 leading byte (>= 0x80) seen in the `Char` state.
    pub fn new(first: u8) -> Self {
        let need = match first {
            0xC0..=0xDF => 1,
            0xE0..=0xEF => 2,
            0xF0..=0xF7 => 3,
            // Not a valid leading byte (e.g. a stray continuation byte).
            _ => 0,
        };

        Self {
            buf: vec![first],
            need,
        }
    }

    pub fn parse(&mut self, key: u8) -> ParseControlFlow {
        // Invalid leading byte, or the next byte is not a continuation byte:
        // drop the partial sequence rather than emit garbage.
        if self.need == 0 || !(0x80..=0xBF).contains(&key) {
            return control_flow!(break);
        }

        self.buf.push(key);

        if self.buf.len() < self.need + 1 {
            return control_flow!(continue);
        }

        let event = std::str::from_utf8(&self.buf)
            .ok()
            .and_then(|s| s.chars().next())
            .map(|ch| Event::KeyPress {
                key: Key {
                    char: ch as u32,
                    modifiers: KeyModifiers::default(),
                },
            });

        control_flow!(break event)
    }
}
