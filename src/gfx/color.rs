use super::Vector3;
use crate::impl_vector_overload;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Color<T: Copy = u8> {
    pub r: T,
    pub g: T,
    pub b: T,
}

impl Color {
    // Name shadows `FromIterator::from_iter` but the signature differs
    // (takes `&mut iterator`, returns `Option`). Renaming would ripple
    // through every call site; the confusion is captured in the comment.
    #[allow(clippy::should_implement_trait)]
    pub fn from_iter<'a, T>(iter: &mut T) -> Option<Color>
    where
        T: Iterator<Item = &'a u8>,
    {
        let (b, g, r, _) = (iter.next(), iter.next(), iter.next(), iter.next());

        Some(Color::<u8>::new(*r?, *g?, *b?))
    }

    pub fn black() -> Color {
        Color::<u8>::new(0, 0, 0)
    }

    /// Per-channel photographic negative (`255 - c`). Used by the terminal
    /// renderer's color-inversion toggle (issue #181) to flip the rendered
    /// page between its original colors and a high-contrast inverse without
    /// touching the Chromium-side raster. Involutive: `c.invert().invert() == c`.
    pub fn invert(self) -> Color {
        Color::<u8>::new(255 - self.r, 255 - self.g, 255 - self.b)
    }
}

impl_vector_overload!(Color r g b);

#[cfg(test)]
mod tests {
    use super::Color;

    #[test]
    fn invert_black_is_white() {
        assert_eq!(Color::new(0, 0, 0).invert(), Color::new(255, 255, 255));
    }

    #[test]
    fn invert_white_is_black() {
        assert_eq!(Color::new(255, 255, 255).invert(), Color::new(0, 0, 0));
    }

    #[test]
    fn invert_per_channel() {
        assert_eq!(Color::new(10, 128, 200).invert(), Color::new(245, 127, 55));
    }

    #[test]
    fn invert_is_involutive() {
        let c = Color::new(33, 99, 222);
        assert_eq!(c.invert().invert(), c);
    }
}
