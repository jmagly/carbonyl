//! Sixel output encoder core (#241).
//!
//! This module keeps the sixel-specific work in a pure BGRA8888 encoder plus
//! small terminal-frame helpers. The default quadrant renderer remains outside
//! this module and is still the fallback path for normal terminal sessions.

use std::{
    collections::BTreeMap,
    io::{self, Write},
};

use crate::gfx::{Rect, Size};

const SIXEL_DCS: &[u8] = b"\x1bPq";
const SIXEL_ST: &[u8] = b"\x1b\\";
const MAX_SIXEL_COLORS: usize = 256;

/// Encode the damaged BGRA8888 source region as a complete sixel DCS sequence.
///
/// `src` is BGRA8888 (byte order B, G, R, A) with dimensions `src_size`.
/// `damage` is clipped to the source bounds. If the clipped region is empty,
/// this returns an empty vector so callers can treat it as a no-op frame.
pub fn bgra_to_sixel(src: &[u8], src_size: Size, damage: Rect) -> Result<Vec<u8>, SixelError> {
    Ok(encode_sixel(src, src_size, damage)?.bytes)
}

/// Return size/palette metadata for the sixel encoding of a damaged region.
///
/// This intentionally performs the same encoding as `bgra_to_sixel`; callers
/// can use it for #241 size/perf measurement without adding a separate code
/// path whose behavior could drift from the emitted terminal payload.
pub fn measure_sixel(src: &[u8], src_size: Size, damage: Rect) -> Result<SixelStats, SixelError> {
    Ok(encode_sixel(src, src_size, damage)?.stats)
}

/// Write a complete live sixel frame at the terminal origin.
///
/// This helper owns only terminal framing, not encoding. It clears the alt
/// screen, homes the cursor, writes the DCS payload, and flushes. Keeping it
/// generic over `Write` makes the terminal behavior unit-testable.
pub fn write_sixel_frame<W: Write>(
    out: &mut W,
    src: &[u8],
    src_size: Size,
) -> Result<(), SixelFrameError> {
    let sixel = bgra_to_sixel(
        src,
        src_size,
        Rect::new(0, 0, src_size.width, src_size.height),
    )?;
    if sixel.is_empty() {
        return Ok(());
    }

    out.write_all(b"\x1b[?25l\x1b[H\x1b[2J")?;
    out.write_all(&sixel)?;
    out.flush()?;

    Ok(())
}

#[derive(Debug, PartialEq, Eq)]
pub enum SixelError {
    InvalidSourceLength { expected: usize, actual: usize },
}

impl std::fmt::Display for SixelError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SixelError::InvalidSourceLength { expected, actual } => write!(
                f,
                "invalid BGRA source length: expected at least {expected} bytes, got {actual}"
            ),
        }
    }
}

impl std::error::Error for SixelError {}

#[derive(Debug)]
pub enum SixelFrameError {
    Encode(SixelError),
    Io(io::Error),
}

impl std::fmt::Display for SixelFrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SixelFrameError::Encode(err) => err.fmt(f),
            SixelFrameError::Io(err) => err.fmt(f),
        }
    }
}

impl std::error::Error for SixelFrameError {}

impl From<SixelError> for SixelFrameError {
    fn from(err: SixelError) -> Self {
        Self::Encode(err)
    }
}

impl From<io::Error> for SixelFrameError {
    fn from(err: io::Error) -> Self {
        Self::Io(err)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SixelStats {
    pub width: usize,
    pub height: usize,
    pub source_bytes: usize,
    pub encoded_bytes: usize,
    pub colors: usize,
    pub palette_mode: SixelPaletteMode,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SixelPaletteMode {
    Empty,
    Exact,
    Rgb332,
}

struct EncodedSixel {
    bytes: Vec<u8>,
    stats: SixelStats,
}

fn encode_sixel(src: &[u8], src_size: Size, damage: Rect) -> Result<EncodedSixel, SixelError> {
    let region = Region::clip(src, src_size, damage)?;
    if region.is_empty() {
        return Ok(EncodedSixel {
            bytes: Vec::new(),
            stats: SixelStats {
                width: 0,
                height: 0,
                source_bytes: 0,
                encoded_bytes: 0,
                colors: 0,
                palette_mode: SixelPaletteMode::Empty,
            },
        });
    }

    let (indexed, palette, palette_mode) = build_indexed_pixels(src, src_size, region);
    let mut bytes = Vec::new();

    bytes.extend_from_slice(SIXEL_DCS);
    append_raster_attributes(&mut bytes, region.width(), region.height());
    append_palette(&mut bytes, &palette);
    append_sixel_pixels(
        &mut bytes,
        &indexed,
        region.width(),
        region.height(),
        palette.len(),
    );
    bytes.extend_from_slice(SIXEL_ST);

    Ok(EncodedSixel {
        stats: SixelStats {
            width: region.width(),
            height: region.height(),
            source_bytes: region.width() * region.height() * 4,
            encoded_bytes: bytes.len(),
            colors: palette.len(),
            palette_mode,
        },
        bytes,
    })
}

#[derive(Clone, Copy)]
struct Region {
    x0: usize,
    y0: usize,
    x1: usize,
    y1: usize,
}

impl Region {
    fn clip(src: &[u8], src_size: Size, damage: Rect) -> Result<Self, SixelError> {
        let src_w = src_size.width as usize;
        let src_h = src_size.height as usize;
        let expected = src_w.saturating_mul(src_h).saturating_mul(4);
        if src.len() < expected {
            return Err(SixelError::InvalidSourceLength {
                expected,
                actual: src.len(),
            });
        }

        let x0 = damage.origin.x.clamp(0, src_size.width as i32) as usize;
        let y0 = damage.origin.y.clamp(0, src_size.height as i32) as usize;
        let x1 = (damage.origin.x as i64 + damage.size.width as i64).clamp(0, src_size.width as i64)
            as usize;
        let y1 = (damage.origin.y as i64 + damage.size.height as i64)
            .clamp(0, src_size.height as i64) as usize;

        Ok(Self { x0, y0, x1, y1 })
    }

    fn width(self) -> usize {
        self.x1.saturating_sub(self.x0)
    }

    fn height(self) -> usize {
        self.y1.saturating_sub(self.y0)
    }

    fn is_empty(self) -> bool {
        self.width() == 0 || self.height() == 0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct Rgb {
    r: u8,
    g: u8,
    b: u8,
}

fn build_indexed_pixels(
    src: &[u8],
    src_size: Size,
    region: Region,
) -> (Vec<u8>, Vec<Rgb>, SixelPaletteMode) {
    let mut pixels = Vec::with_capacity(region.width() * region.height());
    let mut exact_palette = BTreeMap::<Rgb, ()>::new();
    let mut use_quantized_palette = false;

    for y in region.y0..region.y1 {
        for x in region.x0..region.x1 {
            let rgb = read_rgb(src, src_size.width as usize, x, y);
            if !use_quantized_palette {
                let next = exact_palette.len();
                if next < MAX_SIXEL_COLORS {
                    exact_palette.entry(rgb).or_insert(());
                } else {
                    use_quantized_palette = true;
                }
            }
            pixels.push(rgb);
        }
    }

    if use_quantized_palette {
        let (indexed, palette) = build_rgb332_pixels(&pixels);
        (indexed, palette, SixelPaletteMode::Rgb332)
    } else {
        let palette: Vec<Rgb> = exact_palette.keys().copied().collect();
        let index_by_color = palette
            .iter()
            .enumerate()
            .map(|(index, rgb)| (*rgb, index as u8))
            .collect::<BTreeMap<_, _>>();
        let indexed = pixels
            .iter()
            .map(|rgb| index_by_color[rgb])
            .collect::<Vec<_>>();
        (indexed, palette, SixelPaletteMode::Exact)
    }
}

fn read_rgb(src: &[u8], stride_pixels: usize, x: usize, y: usize) -> Rgb {
    let base = (x + y * stride_pixels) * 4;
    Rgb {
        r: src[base + 2],
        g: src[base + 1],
        b: src[base],
    }
}

fn build_rgb332_pixels(pixels: &[Rgb]) -> (Vec<u8>, Vec<Rgb>) {
    let indexed = pixels
        .iter()
        .map(|rgb| {
            let r = rgb.r >> 5;
            let g = rgb.g >> 5;
            let b = rgb.b >> 6;
            (r << 5) | (g << 2) | b
        })
        .collect::<Vec<_>>();

    let palette = (0..=u8::MAX)
        .map(|index| {
            let r = (index >> 5) & 0x07;
            let g = (index >> 2) & 0x07;
            let b = index & 0x03;
            Rgb {
                r: scale_bits(r, 7),
                g: scale_bits(g, 7),
                b: scale_bits(b, 3),
            }
        })
        .collect();

    (indexed, palette)
}

fn scale_bits(value: u8, max: u8) -> u8 {
    ((value as u16 * 255 + (max as u16 / 2)) / max as u16) as u8
}

fn append_raster_attributes(out: &mut Vec<u8>, width: usize, height: usize) {
    out.extend_from_slice(format!("\"1;1;{width};{height}").as_bytes());
}

fn append_palette(out: &mut Vec<u8>, palette: &[Rgb]) {
    for (index, rgb) in palette.iter().enumerate() {
        out.extend_from_slice(
            format!(
                "#{index};2;{};{};{}",
                percent(rgb.r),
                percent(rgb.g),
                percent(rgb.b)
            )
            .as_bytes(),
        );
    }
}

fn percent(sample: u8) -> u8 {
    ((sample as u16 * 100 + 127) / 255) as u8
}

fn append_sixel_pixels(
    out: &mut Vec<u8>,
    indexed: &[u8],
    width: usize,
    height: usize,
    colors: usize,
) {
    let bands = height.div_ceil(6);

    for band in 0..bands {
        let y_base = band * 6;
        let mut emitted_plane = false;
        for color in 0..colors {
            let mut columns = Vec::with_capacity(width);
            let mut active = false;
            for x in 0..width {
                let mut bits = 0u8;
                for bit in 0..6 {
                    let y = y_base + bit;
                    if y < height && indexed[x + y * width] as usize == color {
                        bits |= 1 << bit;
                    }
                }
                active |= bits != 0;
                columns.push(0x3f + bits);
            }

            if !active {
                continue;
            }

            if emitted_plane {
                out.push(b'$');
            }
            emitted_plane = true;
            out.extend_from_slice(format!("#{color}").as_bytes());
            append_sixel_columns(out, &columns);
        }
        if band + 1 < bands {
            out.push(b'-');
        }
    }
}

fn append_sixel_columns(out: &mut Vec<u8>, columns: &[u8]) {
    let last_non_empty = columns
        .iter()
        .rposition(|&column| column != b'?')
        .unwrap_or(0);
    let columns = &columns[..=last_non_empty];
    let mut index = 0;

    while index < columns.len() {
        let ch = columns[index];
        let mut run = 1;
        while index + run < columns.len() && columns[index + run] == ch {
            run += 1;
        }

        if run >= 4 {
            out.extend_from_slice(format!("!{run}").as_bytes());
            out.push(ch);
        } else {
            for _ in 0..run {
                out.push(ch);
            }
        }

        index += run;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bgra(pixels: &[(u8, u8, u8)]) -> Vec<u8> {
        let mut out = Vec::with_capacity(pixels.len() * 4);
        for &(r, g, b) in pixels {
            out.extend_from_slice(&[b, g, r, 0xff]);
        }
        out
    }

    #[test]
    fn encodes_complete_dcs_with_raster_attributes_and_palette() {
        let src = bgra(&[(255, 0, 0)]);
        let out = bgra_to_sixel(&src, Size::new(1, 1), Rect::new(0, 0, 1, 1)).unwrap();
        let text = String::from_utf8(out).unwrap();

        assert!(text.starts_with("\x1bPq\"1;1;1;1"));
        assert!(text.contains("#0;2;100;0;0"));
        assert!(text.ends_with("\x1b\\"));
    }

    #[test]
    fn sixel_bits_pack_six_vertical_pixels_per_column() {
        let src = bgra(&[
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
        ]);
        let out = bgra_to_sixel(&src, Size::new(1, 6), Rect::new(0, 0, 1, 6)).unwrap();
        let text = String::from_utf8(out).unwrap();

        assert!(text.contains("#0~"));
    }

    #[test]
    fn emits_one_plane_per_palette_color() {
        let src = bgra(&[
            (255, 0, 0),
            (0, 0, 255),
            (255, 0, 0),
            (0, 0, 255),
            (255, 0, 0),
            (0, 0, 255),
        ]);
        let out = bgra_to_sixel(&src, Size::new(1, 6), Rect::new(0, 0, 1, 6)).unwrap();
        let text = String::from_utf8(out).unwrap();

        assert!(text.contains("#0;2;0;0;100"));
        assert!(text.contains("#1;2;100;0;0"));
        assert!(text.contains("#0i$#1T"));
    }

    #[test]
    fn skips_palette_colors_absent_from_a_band() {
        let src = bgra(&[
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (0, 0, 255),
        ]);
        let out = bgra_to_sixel(&src, Size::new(1, 7), Rect::new(0, 0, 1, 7)).unwrap();
        let text = String::from_utf8(out).unwrap();

        assert!(text.contains("#1~-#0@"));
        assert!(!text.contains("#0~$#1?"));
    }

    #[test]
    fn compresses_repeated_sixel_columns() {
        let src = bgra(&[
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
            (255, 0, 0),
        ]);
        let out = bgra_to_sixel(&src, Size::new(8, 1), Rect::new(0, 0, 8, 1)).unwrap();
        let text = String::from_utf8(out).unwrap();

        assert!(text.contains("#0!8@"));
    }

    #[test]
    fn clips_damage_to_source_bounds() {
        let src = bgra(&[(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255)]);
        let out = bgra_to_sixel(&src, Size::new(2, 2), Rect::new(1, 0, 10, 10)).unwrap();
        let text = String::from_utf8(out).unwrap();

        assert!(text.starts_with("\x1bPq\"1;1;1;2"));
        assert!(text.contains("#0;2;0;100;0"));
        assert!(text.contains("#1;2;100;100;100"));
    }

    #[test]
    fn clips_negative_damage_origin_to_intersection() {
        let src = bgra(&[(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255)]);
        let stats = measure_sixel(&src, Size::new(2, 2), Rect::new(-1, -1, 2, 2)).unwrap();

        assert_eq!(
            stats,
            SixelStats {
                width: 1,
                height: 1,
                source_bytes: 4,
                encoded_bytes: bgra_to_sixel(&src, Size::new(2, 2), Rect::new(-1, -1, 2, 2))
                    .unwrap()
                    .len(),
                colors: 1,
                palette_mode: SixelPaletteMode::Exact,
            }
        );
    }

    #[test]
    fn out_of_bounds_damage_is_noop() {
        let src = bgra(&[(255, 0, 0)]);
        let out = bgra_to_sixel(&src, Size::new(1, 1), Rect::new(9, 9, 1, 1)).unwrap();

        assert!(out.is_empty());
    }

    #[test]
    fn measures_empty_damage_as_zero_bytes() {
        let src = bgra(&[(255, 0, 0)]);
        let stats = measure_sixel(&src, Size::new(1, 1), Rect::new(9, 9, 1, 1)).unwrap();

        assert_eq!(
            stats,
            SixelStats {
                width: 0,
                height: 0,
                source_bytes: 0,
                encoded_bytes: 0,
                colors: 0,
                palette_mode: SixelPaletteMode::Empty,
            }
        );
    }

    #[test]
    fn measures_exact_palette_output() {
        let src = bgra(&[(255, 0, 0), (0, 255, 0)]);
        let encoded = bgra_to_sixel(&src, Size::new(2, 1), Rect::new(0, 0, 2, 1)).unwrap();
        let stats = measure_sixel(&src, Size::new(2, 1), Rect::new(0, 0, 2, 1)).unwrap();

        assert_eq!(
            stats,
            SixelStats {
                width: 2,
                height: 1,
                source_bytes: 8,
                encoded_bytes: encoded.len(),
                colors: 2,
                palette_mode: SixelPaletteMode::Exact,
            }
        );
    }

    #[test]
    fn measures_rgb332_fallback_output() {
        let pixels = (0..257)
            .map(|i| {
                let i = i as u16;
                (
                    ((i % 17) * 15) as u8,
                    ((i / 17) * 17) as u8,
                    ((i % 5) * 51) as u8,
                )
            })
            .collect::<Vec<_>>();
        let src = bgra(&pixels);
        let stats = measure_sixel(&src, Size::new(257, 1), Rect::new(0, 0, 257, 1)).unwrap();

        assert_eq!(stats.width, 257);
        assert_eq!(stats.height, 1);
        assert_eq!(stats.source_bytes, 257 * 4);
        assert!(stats.encoded_bytes > stats.source_bytes);
        assert_eq!(stats.colors, 256);
        assert_eq!(stats.palette_mode, SixelPaletteMode::Rgb332);
    }

    #[test]
    fn rejects_too_short_source_buffer() {
        let err = bgra_to_sixel(&[], Size::new(1, 1), Rect::new(0, 0, 1, 1)).unwrap_err();

        assert_eq!(
            err,
            SixelError::InvalidSourceLength {
                expected: 4,
                actual: 0
            }
        );
    }

    #[test]
    fn write_frame_homes_clears_and_flushes_sixel() {
        let src = bgra(&[(255, 0, 0)]);
        let mut out = Vec::new();

        write_sixel_frame(&mut out, &src, Size::new(1, 1)).unwrap();
        let text = String::from_utf8(out).unwrap();

        assert!(text.starts_with("\x1b[?25l\x1b[H\x1b[2J\x1bPq"));
        assert!(text.contains("#0;2;100;0;0"));
        assert!(text.ends_with("\x1b\\"));
    }
}
