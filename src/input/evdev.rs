//! evdev input source (#125 cycle 2 — framebuffer-mode input).
//!
//! In framebuffer mode there is no PTY emitting xterm escape sequences for the
//! stdin parser, so a bare console/kiosk has no input. This module reads Linux
//! `/dev/input/event*` devices directly and produces the **same** `Event`s the
//! terminal parser produces, so the bridge's listen loop stays source-agnostic
//! (per the evdev/uinput precedent in the Trusted Automation work, #58/#57).
//!
//! Design:
//! - The pure mapping core (`DeviceState`, `keycode_to_byte`) is unit-tested
//!   without a device: raw `InputEvent`s in, `Event`s out.
//! - The impure shell (`listen_evdev`) discovers readable `event*` nodes, reads
//!   each on its own thread, and funnels decoded `Event` frames through an mpsc
//!   channel to a single callback — mirroring `listen()`'s `FnMut(Vec<Event>)`.
//!
//! Coordinates: pointer motion is accumulated in device pixels and reported in
//! cell basis (`px / 2`, `py / 4`) so the bridge's existing `window.scale`
//! `(2, 4)` recovers device pixels for the browser — no bridge-side scaling
//! change needed (see docs/framebuffer-backend.md).

use std::fs::{read_dir, File};
use std::io::{self, Read};
use std::path::PathBuf;
use std::sync::mpsc;
use std::thread;

use crate::input::{Event, Key, KeyModifiers};
use crate::utils::log;

/// Linux `struct input_event` on 64-bit (`time` is a 16-byte `timeval`).
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct InputEvent {
    pub tv_sec: i64,
    pub tv_usec: i64,
    pub kind: u16,
    pub code: u16,
    pub value: i32,
}

const INPUT_EVENT_SIZE: usize = std::mem::size_of::<InputEvent>();

// Event types (`<linux/input-event-codes.h>`).
const EV_SYN: u16 = 0x00;
const EV_KEY: u16 = 0x01;
const EV_REL: u16 = 0x02;

// Relative axes.
const REL_X: u16 = 0x00;
const REL_Y: u16 = 0x01;
const REL_WHEEL: u16 = 0x08;

// Pointer buttons.
const BTN_LEFT: u16 = 0x110;
const BTN_RIGHT: u16 = 0x111;
const BTN_MIDDLE: u16 = 0x112;

// Modifier keycodes.
const KEY_LEFTSHIFT: u16 = 42;
const KEY_RIGHTSHIFT: u16 = 54;
const KEY_LEFTCTRL: u16 = 29;
const KEY_RIGHTCTRL: u16 = 97;
const KEY_LEFTALT: u16 = 56;
const KEY_RIGHTALT: u16 = 100;
const KEY_LEFTMETA: u16 = 125;
const KEY_RIGHTMETA: u16 = 126;

// Key value semantics.
const KEY_RELEASE: i32 = 0;
const KEY_PRESS: i32 = 1;
const KEY_REPEAT: i32 = 2;

/// Map a Linux keycode + shift state to the byte the terminal parser would
/// produce. Control chars for the arrows match `keyboard.rs` (Up/Down/Right/Left
/// = 0x11/0x12/0x13/0x14). Returns `None` for keys with no byte mapping
/// (modifiers, function keys, unmapped codes).
pub fn keycode_to_byte(code: u16, shift: bool) -> Option<u8> {
    // (unshifted, shifted) for the US QWERTY layout.
    let pair: (u8, u8) = match code {
        // Digit row
        2 => (b'1', b'!'),
        3 => (b'2', b'@'),
        4 => (b'3', b'#'),
        5 => (b'4', b'$'),
        6 => (b'5', b'%'),
        7 => (b'6', b'^'),
        8 => (b'7', b'&'),
        9 => (b'8', b'*'),
        10 => (b'9', b'('),
        11 => (b'0', b')'),
        12 => (b'-', b'_'),
        13 => (b'=', b'+'),
        // Top letter row
        16 => (b'q', b'Q'),
        17 => (b'w', b'W'),
        18 => (b'e', b'E'),
        19 => (b'r', b'R'),
        20 => (b't', b'T'),
        21 => (b'y', b'Y'),
        22 => (b'u', b'U'),
        23 => (b'i', b'I'),
        24 => (b'o', b'O'),
        25 => (b'p', b'P'),
        26 => (b'[', b'{'),
        27 => (b']', b'}'),
        // Home letter row
        30 => (b'a', b'A'),
        31 => (b's', b'S'),
        32 => (b'd', b'D'),
        33 => (b'f', b'F'),
        34 => (b'g', b'G'),
        35 => (b'h', b'H'),
        36 => (b'j', b'J'),
        37 => (b'k', b'K'),
        38 => (b'l', b'L'),
        39 => (b';', b':'),
        40 => (b'\'', b'"'),
        41 => (b'`', b'~'),
        43 => (b'\\', b'|'),
        // Bottom letter row
        44 => (b'z', b'Z'),
        45 => (b'x', b'X'),
        46 => (b'c', b'C'),
        47 => (b'v', b'V'),
        48 => (b'b', b'B'),
        49 => (b'n', b'N'),
        50 => (b'm', b'M'),
        51 => (b',', b'<'),
        52 => (b'.', b'>'),
        53 => (b'/', b'?'),
        // Whitespace / control bytes (shift-invariant)
        57 => return Some(b' '), // SPACE
        28 => return Some(0x0d), // ENTER -> CR
        15 => return Some(0x09), // TAB
        14 => return Some(0x7f), // BACKSPACE -> DEL
        1 => return Some(0x1b),  // ESC
        // Arrows -> control bytes matching keyboard.rs
        103 => return Some(0x11), // UP
        108 => return Some(0x12), // DOWN
        106 => return Some(0x13), // RIGHT
        105 => return Some(0x14), // LEFT
        _ => return None,
    };

    Some(if shift { pair.1 } else { pair.0 })
}

fn is_modifier(code: u16) -> bool {
    matches!(
        code,
        KEY_LEFTSHIFT
            | KEY_RIGHTSHIFT
            | KEY_LEFTCTRL
            | KEY_RIGHTCTRL
            | KEY_LEFTALT
            | KEY_RIGHTALT
            | KEY_LEFTMETA
            | KEY_RIGHTMETA
    )
}

/// Per-device decode state: modifier flags (keyboard) and accumulated pointer
/// position in device pixels (mouse). A device only exercises the parts it
/// emits, so one `DeviceState` per device thread is correct.
#[derive(Default)]
pub struct DeviceState {
    shift: bool,
    control: bool,
    alt: bool,
    meta: bool,
    // Accumulated pointer in device pixels (clamped at 0).
    px: i32,
    py: i32,
    moved: bool,
}

impl DeviceState {
    pub fn new() -> DeviceState {
        DeviceState::default()
    }

    fn modifiers(&self) -> KeyModifiers {
        KeyModifiers {
            alt: self.alt,
            meta: self.meta,
            shift: self.shift,
            control: self.control,
        }
    }

    /// Current pointer in cell basis (bridge scales by `(2, 4)` to recover px).
    fn cell(&self) -> (usize, usize) {
        ((self.px / 2).max(0) as usize, (self.py / 4).max(0) as usize)
    }

    /// Feed one raw event; returns an `Event` to emit, if any. Pointer motion is
    /// accumulated and flushed as a single `MouseMove` on `EV_SYN`.
    pub fn handle(&mut self, ev: InputEvent) -> Option<Event> {
        match ev.kind {
            EV_KEY => self.handle_key(ev.code, ev.value),
            EV_REL => {
                match ev.code {
                    REL_X => {
                        self.px = (self.px + ev.value).max(0);
                        self.moved = true;
                    }
                    REL_Y => {
                        self.py = (self.py + ev.value).max(0);
                        self.moved = true;
                    }
                    REL_WHEEL => {
                        // evdev wheel: +1 per notch up, -1 down — matches the
                        // terminal Scroll convention.
                        return Some(Event::Scroll {
                            delta: ev.value as isize,
                        });
                    }
                    _ => {}
                }
                None
            }
            EV_SYN => {
                if std::mem::take(&mut self.moved) {
                    let (col, row) = self.cell();
                    Some(Event::MouseMove { row, col })
                } else {
                    None
                }
            }
            _ => None,
        }
    }

    fn handle_key(&mut self, code: u16, value: i32) -> Option<Event> {
        if is_modifier(code) {
            let down = value != KEY_RELEASE;
            match code {
                KEY_LEFTSHIFT | KEY_RIGHTSHIFT => self.shift = down,
                KEY_LEFTCTRL | KEY_RIGHTCTRL => self.control = down,
                KEY_LEFTALT | KEY_RIGHTALT => self.alt = down,
                KEY_LEFTMETA | KEY_RIGHTMETA => self.meta = down,
                _ => {}
            }
            return None;
        }

        let (col, row) = self.cell();
        match code {
            BTN_LEFT => match value {
                KEY_PRESS => return Some(Event::MouseDown { row, col }),
                KEY_RELEASE => return Some(Event::MouseUp { row, col }),
                _ => return None,
            },
            // Right/middle have no distinct terminal Event; treat as left for now.
            BTN_RIGHT | BTN_MIDDLE => match value {
                KEY_PRESS => return Some(Event::MouseDown { row, col }),
                KEY_RELEASE => return Some(Event::MouseUp { row, col }),
                _ => return None,
            },
            _ => {}
        }

        // Keyboard key: emit on press and repeat (not release).
        if value == KEY_PRESS || value == KEY_REPEAT {
            if let Some(char) = keycode_to_byte(code, self.shift) {
                return Some(Event::KeyPress {
                    key: Key {
                        char,
                        modifiers: self.modifiers(),
                    },
                });
            }
        }
        None
    }
}

/// Discover readable `/dev/input/event*` device nodes.
fn discover_devices() -> Vec<PathBuf> {
    let mut devices = Vec::new();
    if let Ok(entries) = read_dir("/dev/input") {
        for entry in entries.flatten() {
            let path = entry.path();
            if path
                .file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.starts_with("event"))
            {
                devices.push(path);
            }
        }
    }
    devices.sort();
    devices
}

/// Read one device to end-of-stream, decoding `Event` frames and forwarding
/// them over `tx`. Each `EV_SYN`-terminated batch is sent as one `Vec<Event>`.
fn read_device(mut file: File, tx: mpsc::Sender<Vec<Event>>) {
    let mut state = DeviceState::new();
    let mut buf = [0u8; INPUT_EVENT_SIZE * 32];
    let mut batch: Vec<Event> = Vec::new();

    loop {
        let n = match file.read(&mut buf) {
            Ok(0) => return,
            Ok(n) => n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(_) => return,
        };
        // Decode whole input_event records; ignore any trailing partial record.
        for chunk in buf[..n].chunks_exact(INPUT_EVENT_SIZE) {
            let ev = parse_input_event(chunk);
            let is_syn = ev.kind == EV_SYN;
            if let Some(event) = state.handle(ev) {
                batch.push(event);
            }
            if is_syn && !batch.is_empty() && tx.send(std::mem::take(&mut batch)).is_err() {
                return;
            }
        }
    }
}

/// Decode a 24-byte little-endian `input_event` record.
fn parse_input_event(bytes: &[u8]) -> InputEvent {
    debug_assert_eq!(bytes.len(), INPUT_EVENT_SIZE);
    let i64_at = |o: usize| i64::from_ne_bytes(bytes[o..o + 8].try_into().unwrap());
    let u16_at = |o: usize| u16::from_ne_bytes(bytes[o..o + 2].try_into().unwrap());
    let i32_at = |o: usize| i32::from_ne_bytes(bytes[o..o + 4].try_into().unwrap());
    InputEvent {
        tv_sec: i64_at(0),
        tv_usec: i64_at(8),
        kind: u16_at(16),
        code: u16_at(18),
        value: i32_at(20),
    }
}

/// Listen for input on `/dev/input/event*` and deliver decoded `Event` batches
/// to `callback`, mirroring `listen()`. Blocks until all devices close, so run
/// from a dedicated thread. Returns an error only if no readable device exists
/// (caller logs and falls back); per-device read errors end that device quietly.
pub fn listen_evdev<F>(mut callback: F) -> io::Result<()>
where
    F: FnMut(Vec<Event>),
{
    let devices = discover_devices();
    let (tx, rx) = mpsc::channel::<Vec<Event>>();
    let mut opened = 0;

    for path in devices {
        match File::open(&path) {
            Ok(file) => {
                let tx = tx.clone();
                thread::spawn(move || read_device(file, tx));
                opened += 1;
            }
            Err(e) => log::debug!("evdev: skip {}: {e}", path.display()),
        }
    }
    // Drop our own sender so the channel closes once every device thread ends.
    drop(tx);

    if opened == 0 {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "no readable /dev/input/event* device (need the `video`/`input` group or root)",
        ));
    }
    log::debug!("evdev: listening on {opened} device(s)");

    while let Ok(events) = rx.recv() {
        callback(events);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ev(kind: u16, code: u16, value: i32) -> InputEvent {
        InputEvent {
            tv_sec: 0,
            tv_usec: 0,
            kind,
            code,
            value,
        }
    }

    #[test]
    fn keycode_letters_respect_shift() {
        assert_eq!(keycode_to_byte(30, false), Some(b'a'));
        assert_eq!(keycode_to_byte(30, true), Some(b'A'));
        assert_eq!(keycode_to_byte(2, false), Some(b'1'));
        assert_eq!(keycode_to_byte(2, true), Some(b'!'));
    }

    #[test]
    fn keycode_control_bytes_and_arrows() {
        assert_eq!(keycode_to_byte(28, false), Some(0x0d)); // enter
        assert_eq!(keycode_to_byte(1, false), Some(0x1b)); // esc
        assert_eq!(keycode_to_byte(103, false), Some(0x11)); // up
        assert_eq!(keycode_to_byte(105, true), Some(0x14)); // left (shift-invariant)
        assert_eq!(keycode_to_byte(0xffff, false), None); // unmapped
    }

    #[test]
    fn key_press_emits_keypress_with_modifiers() {
        let mut s = DeviceState::new();
        // shift down (no event), then 'a' press -> 'A'
        assert!(s.handle(ev(EV_KEY, KEY_LEFTSHIFT, KEY_PRESS)).is_none());
        match s.handle(ev(EV_KEY, 30, KEY_PRESS)) {
            Some(Event::KeyPress { key }) => {
                assert_eq!(key.char, b'A');
                assert!(key.modifiers.shift);
            }
            other => panic!("expected KeyPress, got {other:?}"),
        }
        // release shift, 'a' -> 'a'
        assert!(s.handle(ev(EV_KEY, KEY_LEFTSHIFT, KEY_RELEASE)).is_none());
        match s.handle(ev(EV_KEY, 30, KEY_PRESS)) {
            Some(Event::KeyPress { key }) => assert_eq!(key.char, b'a'),
            other => panic!("expected KeyPress, got {other:?}"),
        }
    }

    #[test]
    fn key_release_does_not_emit() {
        let mut s = DeviceState::new();
        assert!(s.handle(ev(EV_KEY, 30, KEY_RELEASE)).is_none());
    }

    #[test]
    fn relative_motion_flushes_on_syn_in_cell_basis() {
        let mut s = DeviceState::new();
        assert!(s.handle(ev(EV_REL, REL_X, 8)).is_none());
        assert!(s.handle(ev(EV_REL, REL_Y, 16)).is_none());
        match s.handle(ev(EV_SYN, 0, 0)) {
            // 8px / 2 = col 4 ; 16px / 4 = row 4
            Some(Event::MouseMove { row, col }) => assert_eq!((row, col), (4, 4)),
            other => panic!("expected MouseMove, got {other:?}"),
        }
        // A SYN with no motion emits nothing.
        assert!(s.handle(ev(EV_SYN, 0, 0)).is_none());
    }

    #[test]
    fn left_button_maps_to_mouse_down_up() {
        let mut s = DeviceState::new();
        assert!(matches!(
            s.handle(ev(EV_KEY, BTN_LEFT, KEY_PRESS)),
            Some(Event::MouseDown { .. })
        ));
        assert!(matches!(
            s.handle(ev(EV_KEY, BTN_LEFT, KEY_RELEASE)),
            Some(Event::MouseUp { .. })
        ));
    }

    #[test]
    fn wheel_maps_to_scroll() {
        let mut s = DeviceState::new();
        match s.handle(ev(EV_REL, REL_WHEEL, -1)) {
            Some(Event::Scroll { delta }) => assert_eq!(delta, -1),
            other => panic!("expected Scroll, got {other:?}"),
        }
    }

    #[test]
    fn parse_input_event_roundtrips() {
        let mut bytes = [0u8; INPUT_EVENT_SIZE];
        bytes[16..18].copy_from_slice(&EV_KEY.to_ne_bytes());
        bytes[18..20].copy_from_slice(&30u16.to_ne_bytes());
        bytes[20..24].copy_from_slice(&1i32.to_ne_bytes());
        let ev = parse_input_event(&bytes);
        assert_eq!((ev.kind, ev.code, ev.value), (EV_KEY, 30, 1));
    }
}
