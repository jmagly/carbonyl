use crate::gfx::Color;
use crate::utils::FourBits::{self, *};

/// Turn a quadrant of four colors into two colors and a quadrant unicode character.
pub fn binarize_quandrant(
    (x, y, z, w): (Color, Color, Color, Color),
) -> (&'static str, Color, Color) {
    // Step 1: grayscale
    const LUMA: Color<f32> = Color::new(0.299, 0.587, 0.114);
    let (a, b, c, d) = (
        LUMA.dot(x.cast()),
        LUMA.dot(y.cast()),
        LUMA.dot(z.cast()),
        LUMA.dot(w.cast()),
    );
    // Step 2: luminance midpoint
    let min = a.min(b).min(c).min(d);
    let max = a.max(b).max(c).max(d);

    // Step 2.5: near-uniform cells collapse to a single color.
    //
    // Without this, sub-JND luminance noise from antialiased page rasters
    // splits the four pixels at the midpoint and emits a half-block with
    // two slightly-different colors, producing the "phantom highlight box"
    // mottling reported in #74. Threshold of 4.0 is sub-JND for 8-bit luma,
    // so genuine glyph edges still go through the binarization path.
    const UNIFORM_THRESHOLD: f32 = 4.0;
    if max - min < UNIFORM_THRESHOLD {
        let avg = x.avg_with(y).avg_with(z.avg_with(w));
        return ("\u{2588}", avg, avg);
    }

    let mid = min + (max - min) / 2.0;

    // Step 3: average colors based on binary mask
    match FourBits::new(a > mid, b > mid, c > mid, d > mid) {
        B0000 => ("▄", x.avg_with(y), z.avg_with(w)),
        B0001 => ("▖", x.avg_with(y).avg_with(z), w),
        B0010 => ("▗", x.avg_with(y).avg_with(w), z),
        B0011 => ("▄", x.avg_with(y), z.avg_with(w)),
        B0100 => ("▝", x.avg_with(z).avg_with(w), y),
        B0101 => ("▞", x.avg_with(z), y.avg_with(w)),
        B0110 => ("▐", x.avg_with(w), y.avg_with(z)),
        B0111 => ("▘", y.avg_with(z).avg_with(w), x),
        B1000 => ("▘", y.avg_with(z).avg_with(w), x),
        B1001 => ("▌", y.avg_with(z), x.avg_with(w)),
        B1010 => ("▚", y.avg_with(w), x.avg_with(z)),
        B1011 => ("▝", x.avg_with(z).avg_with(w), y),
        B1100 => ("▄", x.avg_with(y), z.avg_with(w)),
        B1101 => ("▗", x.avg_with(y).avg_with(w), z),
        B1110 => ("▖", x.avg_with(y).avg_with(z), w),
        B1111 => ("▄", x.avg_with(y), z.avg_with(w)),
    }
}
