use crate::control_flow;

use super::{Event, ParseControlFlow};

pub struct Keyboard {
    state: State,
}

#[derive(Clone, Debug)]
pub struct Key {
    /// Unicode scalar value. Control/navigation keys use small codes
    /// (e.g. 0x11 Up, 0x7f Backspace); printable input is the full codepoint,
    /// so multi-byte UTF-8 (Cyrillic, CJK, …) survives intact (#178/#217).
    pub char: u32,
    pub modifiers: KeyModifiers,
}

#[derive(Clone, Debug, Default)]
pub struct KeyModifiers {
    pub alt: bool,
    pub meta: bool,
    pub shift: bool,
    pub control: bool,
}

enum State {
    Separator,
    Modifier(u8),
}

impl Default for Keyboard {
    fn default() -> Self {
        Self::new()
    }
}

impl Keyboard {
    pub fn new() -> Self {
        Self {
            state: State::Separator,
        }
    }
    pub fn key(key: u8, modifiers: u8) -> Option<Event> {
        let modifiers = KeyModifiers::parse(modifiers);
        let char: u32 = match key {
            // Up
            b'A' => 0x11,
            // Down
            b'B' => 0x12,
            // Right
            b'C' => 0x13,
            // Left
            b'D' => 0x14,
            _ => return None,
        };

        Some(Event::KeyPress {
            key: Key { char, modifiers },
        })
    }

    pub fn parse(&mut self, key: u8) -> ParseControlFlow {
        self.state = match self.state {
            State::Separator => match key {
                b';' => State::Modifier(0),
                _ => control_flow!(break)?,
            },
            State::Modifier(code) => match key {
                b'0'..=b'9' => State::Modifier(code * 10 + key - b'0'),
                key => control_flow!(break Self::key(key, code))?,
            },
        };

        control_flow!(continue)
    }
}

impl From<u8> for Key {
    fn from(char: u8) -> Self {
        Self {
            char: char as u32,
            modifiers: KeyModifiers::default(),
        }
    }
}

impl Key {
    /// Shift+Tab as a terminal back-tab (CSI Z, terminfo `kcbt`): Tab keycode
    /// with the shift modifier set. xterm sends a bare `ESC [ Z` for Shift+Tab,
    /// carrying no numeric modifier code, so shift is intrinsic here. Forwarding
    /// shift (via the FFI modifier mask, #237) lets Blink's DefaultTabEventHandler
    /// run reverse focus traversal.
    pub fn back_tab() -> Self {
        Self {
            char: 0x09,
            modifiers: KeyModifiers {
                shift: true,
                ..KeyModifiers::default()
            },
        }
    }
}

impl KeyModifiers {
    /// FFI modifier mask delivered to the C++ side alongside the keycode
    /// (`key_press` in src/browser/bridge.rs and renderer.h). Stable carbonyl
    /// ABI — patch 0009 translates it into `blink::WebInputEvent::Modifiers`:
    /// bit0 = shift, bit1 = control, bit2 = alt, bit3 = meta. Keeping our own
    /// layout (rather than reusing Blink's enum values) decouples the Rust side
    /// from Chromium internals; the translation is explicit on the C++ side.
    pub fn mask(&self) -> u32 {
        (self.shift as u32)
            | (self.control as u32) << 1
            | (self.alt as u32) << 2
            | (self.meta as u32) << 3
    }

    pub fn parse(key: u8) -> Self {
        let (alt, meta, shift, control) = (0b1000, 0b0100, 0b0010, 0b0001);
        let mask = match key {
            2 => shift,
            3 => alt,
            4 => shift | alt,
            5 => control,
            6 => shift | control,
            7 => alt | control,
            8 => shift | alt | control,
            9 => meta,
            10 => meta | shift,
            11 => meta | alt,
            12 => meta | alt | shift,
            13 => meta | control,
            14 => meta | control | shift,
            15 => meta | control | alt,
            16 => meta | control | alt | shift,
            _ => 0,
        };

        KeyModifiers {
            alt: alt & mask != 0,
            meta: meta & mask != 0,
            shift: shift & mask != 0,
            control: control & mask != 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mask_bit_layout() {
        // bit0 shift, bit1 control, bit2 alt, bit3 meta.
        assert_eq!(KeyModifiers::default().mask(), 0);
        assert_eq!(
            KeyModifiers { shift: true, ..Default::default() }.mask(),
            0b0001
        );
        assert_eq!(
            KeyModifiers { control: true, ..Default::default() }.mask(),
            0b0010
        );
        assert_eq!(
            KeyModifiers { alt: true, ..Default::default() }.mask(),
            0b0100
        );
        assert_eq!(
            KeyModifiers { meta: true, ..Default::default() }.mask(),
            0b1000
        );
        assert_eq!(
            KeyModifiers { shift: true, control: true, alt: true, meta: true }.mask(),
            0b1111
        );
    }

    #[test]
    fn back_tab_is_tab_with_shift() {
        let k = Key::back_tab();
        assert_eq!(k.char, 0x09);
        assert!(k.modifiers.shift);
        assert!(!k.modifiers.control);
        assert!(!k.modifiers.alt);
        assert!(!k.modifiers.meta);
        // The FFI mask the bridge forwards for Shift+Tab.
        assert_eq!(k.modifiers.mask(), 0b0001);
    }

    #[test]
    fn parse_csi_modifier_codes_round_trip_to_mask() {
        // CSI 1;<code> arrow path: shift (2), control (5), shift+alt (4).
        assert_eq!(KeyModifiers::parse(2).mask(), 0b0001); // shift
        assert_eq!(KeyModifiers::parse(5).mask(), 0b0010); // control
        assert_eq!(KeyModifiers::parse(4).mask(), 0b0101); // shift+alt
    }
}
