use std::ops::BitAnd;

use crate::{control_flow, utils::log};

use super::{Event, ParseControlFlow};

#[derive(Default, Clone, Debug)]
pub struct Mouse {
    buf: Vec<u8>,
    btn: Option<u32>,
    col: Option<u32>,
    row: Option<u32>,
}

#[derive(Default)]
pub struct LegacyMouse {
    buf: Vec<u8>,
}

impl Mouse {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn parse(&mut self, key: u8) -> ParseControlFlow {
        match key {
            b'm' | b'M' => control_flow!(break self.get(key)),
            b';' => match self.read() {
                None => control_flow!(break),
                Some(()) => control_flow!(continue),
            },
            key => control_flow!(self.buf.push(key); continue),
        }
    }

    fn read(&mut self) -> Option<()> {
        let buf = std::mem::take(&mut self.buf);
        let str = std::str::from_utf8(&buf).ok()?;
        let num = Some(str.parse().ok()?);

        match (self.btn, self.col, self.row) {
            (None, _, _) => self.btn = num,
            (_, None, _) => self.col = num,
            (_, _, None) => self.row = num,
            _ => {
                log::warning!("Malformed mouse sequence");

                return None;
            }
        }

        Some(())
    }

    fn get(&mut self, key: u8) -> Option<Event> {
        let (btn, col, row) = {
            self.read()?;

            (self.btn?, self.col?, self.row?)
        };

        mouse_event(btn, col, row, key == b'm')
    }
}

impl LegacyMouse {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn parse(&mut self, key: u8) -> ParseControlFlow {
        self.buf.push(key);

        if self.buf.len() < 3 {
            return control_flow!(continue);
        }

        let Some(btn) = self.buf[0].checked_sub(32).map(u32::from) else {
            return control_flow!(break);
        };
        let Some(col) = self.buf[1].checked_sub(32).map(u32::from) else {
            return control_flow!(break);
        };
        let Some(row) = self.buf[2].checked_sub(32).map(u32::from) else {
            return control_flow!(break);
        };

        control_flow!(break mouse_event(btn, col, row, btn & 0b11 == 3))
    }
}

enum Mask {
    MouseMove = 0x20,
    ScrollUp = 0x40,
    ScrollDown = 0x41,
}

impl BitAnd<u32> for Mask {
    type Output = bool;

    fn bitand(self, rhs: u32) -> bool {
        let mask = self as u32;

        mask & rhs == mask
    }
}

fn mouse_event(btn: u32, col: u32, row: u32, release: bool) -> Option<Event> {
    if Mask::ScrollDown & btn {
        Some(Event::Scroll { delta: -1 })
    } else if Mask::ScrollUp & btn {
        Some(Event::Scroll { delta: 1 })
    } else {
        let col = col.checked_sub(1)? as usize;
        let row = row.checked_sub(1)? as usize;
        // SGR and legacy low 2 bits select the button: 0=left, 1=middle, 2=right.
        // Legacy release reports encode 3, which does not identify the released
        // button, so treat it as the primary button for click completion.
        let mut button = btn & 0b11;
        if release && button == 3 {
            button = 0;
        }

        if release {
            Some(Event::MouseUp { row, col, button })
        } else if Mask::MouseMove & btn {
            Some(Event::MouseMove { row, col })
        } else {
            Some(Event::MouseDown { row, col, button })
        }
    }
}
