//! Screenshot encoding (#3).
//!
//! Chromium hands the bridge a **BGRA8888** raster (byte order B, G, R, A) via
//! `carbonyl_renderer_draw_bitmap` — the same raster the terminal renderer and
//! the framebuffer sink consume. This module encodes that raster to PNG for
//! screenshot capture, with no CDP round-trip.
//!
//! The encode path is pure (`raster → owned PNG bytes`) so it is unit-tested
//! without a browser. The FFI surface that arms capture, caches the latest
//! frame, and returns the encoded bytes lives in `src/browser/bridge.rs`.
//!
//! HTTP/socket exposure is out of scope here (tracked in carbonyl-fleet#8).

use crate::gfx::Size;

/// Screenshot output format. JPEG is deferred (would add an encoder dep); PNG
/// is the default and only supported format today.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScreenshotFormat {
    Png,
}

impl ScreenshotFormat {
    /// Parse a requested format. Only PNG is implemented today, so every input
    /// maps to `Png` ("jpeg"/"jpg" are accepted by the API but deferred — see
    /// module docs). The parameter is retained for forward-compatibility.
    pub fn parse(_s: &str) -> ScreenshotFormat {
        ScreenshotFormat::Png
    }
}

/// Encode a BGRA8888 raster as a PNG.
///
/// `bgra` is `size.width * size.height * 4` bytes in B, G, R, A order (the byte
/// layout Chromium's software output device produces). Returns the complete PNG
/// file as owned bytes, or `None` if the buffer is too small for the claimed
/// size (caller passed a stale/mismatched frame).
pub fn encode_png(bgra: &[u8], size: Size) -> Option<Vec<u8>> {
    let (w, h) = (size.width as usize, size.height as usize);
    let expected = w.checked_mul(h)?.checked_mul(4)?;
    if w == 0 || h == 0 || bgra.len() < expected {
        return None;
    }

    // BGRA → RGBA: swap the B and R channels; alpha and green stay put.
    let mut rgba = vec![0u8; expected];
    for (dst, src) in rgba
        .chunks_exact_mut(4)
        .zip(bgra[..expected].chunks_exact(4))
    {
        dst[0] = src[2]; // R ← B-position source is B; PNG wants R first
        dst[1] = src[1]; // G
        dst[2] = src[0]; // B
        dst[3] = src[3]; // A
    }

    let mut out = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut out, size.width, size.height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        // Writer borrows `out`; scope it so the borrow ends before we return.
        let mut writer = encoder.write_header().ok()?;
        writer.write_image_data(&rgba).ok()?;
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gfx::Size;

    const PNG_SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', b'\r', b'\n', 0x1a, b'\n'];

    fn sample_bgra() -> (Vec<u8>, Size) {
        // 2x2: red, green, blue, opaque-white — written in BGRA byte order.
        let px = |b, g, r, a| [b, g, r, a];
        let mut buf = Vec::new();
        buf.extend_from_slice(&px(0, 0, 255, 255)); // red
        buf.extend_from_slice(&px(0, 255, 0, 255)); // green
        buf.extend_from_slice(&px(255, 0, 0, 255)); // blue
        buf.extend_from_slice(&px(255, 255, 255, 128)); // semi-transparent white
        (buf, Size::new(2, 2))
    }

    #[test]
    fn encode_png_emits_valid_signature_and_dims() {
        let (bgra, size) = sample_bgra();
        let png = encode_png(&bgra, size).expect("encode");
        assert!(png.len() > PNG_SIGNATURE.len());
        assert_eq!(&png[..8], &PNG_SIGNATURE, "PNG magic");
    }

    #[test]
    fn encode_png_roundtrips_bgra_to_rgba() {
        let (bgra, size) = sample_bgra();
        let png = encode_png(&bgra, size).expect("encode");

        let decoder = png::Decoder::new(png.as_slice());
        let mut reader = decoder.read_info().expect("read_info");
        let info = reader.info();
        assert_eq!((info.width, info.height), (2, 2));
        assert_eq!(info.color_type, png::ColorType::Rgba);

        let mut decoded = vec![0u8; reader.output_buffer_size()];
        let frame = reader.next_frame(&mut decoded).expect("next_frame");
        let rgba = &decoded[..frame.buffer_size()];

        // Swap RGBA back to BGRA and compare to the input raster.
        let mut back = vec![0u8; rgba.len()];
        for (dst, src) in back.chunks_exact_mut(4).zip(rgba.chunks_exact(4)) {
            dst[0] = src[2]; // B
            dst[1] = src[1]; // G
            dst[2] = src[0]; // R
            dst[3] = src[3]; // A
        }
        assert_eq!(back, bgra);
    }

    #[test]
    fn encode_png_rejects_undersized_buffer() {
        // Claims 4x4 (64 bytes) but only provides 16.
        let buf = vec![0u8; 16];
        assert!(encode_png(&buf, Size::new(4, 4)).is_none());
    }

    #[test]
    fn encode_png_rejects_zero_dimension() {
        assert!(encode_png(&[], Size::new(0, 0)).is_none());
    }

    #[test]
    fn format_parse_defaults_to_png() {
        assert_eq!(ScreenshotFormat::parse("png"), ScreenshotFormat::Png);
        assert_eq!(ScreenshotFormat::parse("JPEG"), ScreenshotFormat::Png);
        assert_eq!(ScreenshotFormat::parse(""), ScreenshotFormat::Png);
    }
}
