//! Terminal image-protocol wrappers for encoded raster payloads (#241).
//!
//! These helpers intentionally wrap PNG bytes instead of re-encoding BGRA
//! frames. The dump path can therefore reuse the existing screenshot encoder
//! and emit payloads for terminals that support kitty graphics or iTerm2 inline
//! images without adding another raster dependency.

use std::io::{self, Write};

use crate::gfx::Size;
use crate::output::encode_png;

const BASE64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn encode_kitty_png(png: &[u8], size: Size) -> Vec<u8> {
    let b64 = encode_base64(png);
    let mut out = Vec::with_capacity(b64.len() + 64);
    out.extend_from_slice(
        format!("\x1b_Ga=T,f=100,t=d,s={},v={};", size.width, size.height).as_bytes(),
    );
    out.extend_from_slice(b64.as_bytes());
    out.extend_from_slice(b"\x1b\\");
    out
}

pub fn encode_iterm2_png(png: &[u8], size: Size) -> Vec<u8> {
    let b64 = encode_base64(png);
    let mut out = Vec::with_capacity(b64.len() + 96);
    out.extend_from_slice(
        format!(
            "\x1b]1337;File=inline=1;width={}px;height={}px;preserveAspectRatio=1:",
            size.width, size.height
        )
        .as_bytes(),
    );
    out.extend_from_slice(b64.as_bytes());
    out.push(0x07);
    out
}

pub fn write_kitty_frame<W: Write>(
    out: &mut W,
    src: &[u8],
    src_size: Size,
) -> Result<(), TerminalImageFrameError> {
    write_wrapped_png_frame(out, src, src_size, encode_kitty_png)
}

pub fn write_iterm2_frame<W: Write>(
    out: &mut W,
    src: &[u8],
    src_size: Size,
) -> Result<(), TerminalImageFrameError> {
    write_wrapped_png_frame(out, src, src_size, encode_iterm2_png)
}

fn write_wrapped_png_frame<W: Write>(
    out: &mut W,
    src: &[u8],
    src_size: Size,
    wrap: fn(&[u8], Size) -> Vec<u8>,
) -> Result<(), TerminalImageFrameError> {
    let png = encode_png(src, src_size).ok_or(TerminalImageFrameError::InvalidFrame)?;
    let frame = wrap(&png, src_size);

    out.write_all(b"\x1b[?25l\x1b[H\x1b[2J")?;
    out.write_all(&frame)?;
    out.flush()?;

    Ok(())
}

#[derive(Debug)]
pub enum TerminalImageFrameError {
    InvalidFrame,
    Io(io::Error),
}

impl std::fmt::Display for TerminalImageFrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TerminalImageFrameError::InvalidFrame => write!(f, "invalid BGRA frame"),
            TerminalImageFrameError::Io(err) => err.fmt(f),
        }
    }
}

impl std::error::Error for TerminalImageFrameError {}

impl From<io::Error> for TerminalImageFrameError {
    fn from(err: io::Error) -> Self {
        Self::Io(err)
    }
}

fn encode_base64(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0];
        let b1 = chunk.get(1).copied().unwrap_or(0);
        let b2 = chunk.get(2).copied().unwrap_or(0);
        let n = ((b0 as u32) << 16) | ((b1 as u32) << 8) | b2 as u32;

        out.push(BASE64[((n >> 18) & 0x3f) as usize] as char);
        out.push(BASE64[((n >> 12) & 0x3f) as usize] as char);
        if chunk.len() > 1 {
            out.push(BASE64[((n >> 6) & 0x3f) as usize] as char);
        } else {
            out.push('=');
        }
        if chunk.len() > 2 {
            out.push(BASE64[(n & 0x3f) as usize] as char);
        } else {
            out.push('=');
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_handles_padding_cases() {
        assert_eq!(encode_base64(b""), "");
        assert_eq!(encode_base64(b"f"), "Zg==");
        assert_eq!(encode_base64(b"fo"), "Zm8=");
        assert_eq!(encode_base64(b"foo"), "Zm9v");
        assert_eq!(encode_base64(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn kitty_wraps_png_payload_with_graphics_apc() {
        let out = encode_kitty_png(b"png", Size::new(2, 3));
        let text = String::from_utf8(out).unwrap();

        assert!(text.starts_with("\x1b_Ga=T,f=100,t=d,s=2,v=3;"));
        assert!(text.contains("cG5n"));
        assert!(text.ends_with("\x1b\\"));
    }

    #[test]
    fn iterm2_wraps_png_payload_with_inline_file_osc() {
        let out = encode_iterm2_png(b"png", Size::new(2, 3));
        let text = String::from_utf8(out).unwrap();

        assert!(
            text.starts_with("\x1b]1337;File=inline=1;width=2px;height=3px;preserveAspectRatio=1:")
        );
        assert!(text.contains("cG5n"));
        assert!(text.ends_with('\u{7}'));
    }

    #[test]
    fn write_kitty_frame_homes_clears_and_flushes_image() {
        let src = vec![0, 0, 255, 255];
        let mut out = Vec::new();

        write_kitty_frame(&mut out, &src, Size::new(1, 1)).unwrap();
        let text = String::from_utf8(out).unwrap();

        assert!(text.starts_with("\x1b[?25l\x1b[H\x1b[2J\x1b_G"));
        assert!(text.ends_with("\x1b\\"));
    }

    #[test]
    fn write_iterm2_frame_homes_clears_and_flushes_image() {
        let src = vec![0, 0, 255, 255];
        let mut out = Vec::new();

        write_iterm2_frame(&mut out, &src, Size::new(1, 1)).unwrap();
        let text = String::from_utf8(out).unwrap();

        assert!(text.starts_with("\x1b[?25l\x1b[H\x1b[2J\x1b]1337;File="));
        assert!(text.ends_with('\u{7}'));
    }
}
