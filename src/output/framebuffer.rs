//! Linux framebuffer (`/dev/fb0`) output backend (#125).
//!
//! Renders Chromium frames directly to a Linux framebuffer device so Carbonyl
//! can run at full pixel resolution on a local system TTY without an X11/Wayland
//! session — kiosk, appliance, recovery-console, and bare-metal setups.
//!
//! This module is the **output sink**. The frame source is unchanged: Chromium
//! hands the bridge a BGRA8888 raster (see `Renderer::draw_background` and
//! `bridge.rs` where `draw_background` is called). In framebuffer mode that same
//! raster is converted to the device's native pixel format and blitted to the
//! mapped framebuffer instead of being quantized to terminal cells.
//!
//! ## Status
//!
//! Cycle 1 (this commit) lands the self-contained backend and its pure
//! conversion/blit core (unit-tested). It is **not yet wired into the live
//! render path** — the bridge still drives only the terminal renderer. Routing
//! frames here when `--framebuffer` is set, deriving the browser viewport from
//! the device geometry, and input pairing (controlling-TTY keyboard vs evdev)
//! are follow-up work that requires the full Chromium build + a real console to
//! verify. See `docs/framebuffer-backend.md`.
//!
//! Everything in this module is `dead_code`-allowed until the bridge wiring
//! lands; the logic is exercised by the unit tests below.
#![allow(dead_code)]

use std::{
    fs::{File, OpenOptions},
    io,
    os::unix::io::AsRawFd,
    ptr, slice,
};

use crate::gfx::{Rect, Size};

/// Default framebuffer device when `--framebuffer` is given without a path.
pub const DEFAULT_FB_DEVICE: &str = "/dev/fb0";

// ioctl request numbers from <linux/fb.h>. These are fixed constants in the
// kernel UAPI (not _IOR-encoded), identical across architectures.
const FBIOGET_VSCREENINFO: libc::c_ulong = 0x4600;
const FBIOGET_FSCREENINFO: libc::c_ulong = 0x4602;

/// `struct fb_bitfield` — describes one color channel's bit position.
#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
struct FbBitfield {
    offset: u32,
    length: u32,
    msb_right: u32,
}

/// `struct fb_var_screeninfo` — the full kernel layout. The whole struct must be
/// present (correct size) because `FBIOGET_VSCREENINFO` writes all of it.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct FbVarScreeninfo {
    xres: u32,
    yres: u32,
    xres_virtual: u32,
    yres_virtual: u32,
    xoffset: u32,
    yoffset: u32,
    bits_per_pixel: u32,
    grayscale: u32,
    red: FbBitfield,
    green: FbBitfield,
    blue: FbBitfield,
    transp: FbBitfield,
    nonstd: u32,
    activate: u32,
    height: u32,
    width: u32,
    accel_flags: u32,
    pixclock: u32,
    left_margin: u32,
    right_margin: u32,
    upper_margin: u32,
    lower_margin: u32,
    hsync_len: u32,
    vsync_len: u32,
    sync: u32,
    vmode: u32,
    rotate: u32,
    colorspace: u32,
    reserved: [u32; 4],
}

/// `struct fb_fix_screeninfo` — fixed device properties. Only `line_length` and
/// `smem_len` are consumed, but the full layout is required for the ioctl.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct FbFixScreeninfo {
    id: [u8; 16],
    smem_start: libc::c_ulong,
    smem_len: u32,
    typ: u32,
    type_aux: u32,
    visual: u32,
    xpanstep: u16,
    ypanstep: u16,
    ywrapstep: u16,
    line_length: u32,
    mmio_start: libc::c_ulong,
    mmio_len: u32,
    accel: u32,
    capabilities: u16,
    reserved: [u16; 2],
}

/// One color channel's placement within a packed pixel.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Channel {
    pub offset: u32,
    pub length: u32,
}

impl Channel {
    /// Scale an 8-bit sample into this channel's bit width and shift into place.
    #[inline]
    fn pack(self, sample: u8) -> u32 {
        if self.length == 0 {
            return 0;
        }
        // Take the top `length` bits of the 8-bit sample, then position them.
        let scaled = (sample as u32) >> (8u32.saturating_sub(self.length));
        scaled << self.offset
    }
}

/// Target pixel format derived from the device's `fb_var_screeninfo`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PixelFormat {
    /// Bytes written per pixel (2 for 16bpp, 4 for 32bpp).
    pub bytes_per_pixel: usize,
    pub red: Channel,
    pub green: Channel,
    pub blue: Channel,
}

impl PixelFormat {
    /// Pack an (r, g, b) triple into the device word.
    #[inline]
    pub fn pack(&self, r: u8, g: u8, b: u8) -> u32 {
        self.red.pack(r) | self.green.pack(g) | self.blue.pack(b)
    }
}

/// Failure modes when opening or using a framebuffer device. Each maps to an
/// actionable operator message (see `Display`).
#[derive(Debug)]
pub enum FbError {
    /// Device node does not exist (no framebuffer / wrong path).
    NotFound(String),
    /// Insufficient permissions (typically needs the `video` group or root).
    PermissionDenied(String),
    /// Device is busy / already in use by another process.
    Busy(String),
    /// Opening the device failed for another reason.
    Open(io::Error),
    /// An `FBIOGET_*SCREENINFO` ioctl failed.
    Ioctl(io::Error),
    /// `mmap` of the framebuffer memory failed.
    Mmap(io::Error),
    /// Device bit depth is not supported (only 16bpp and 32bpp handled).
    UnsupportedFormat { bits_per_pixel: u32 },
}

impl std::fmt::Display for FbError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FbError::NotFound(p) => write!(
                f,
                "framebuffer device {p} not found; this kernel/console has no framebuffer \
                 (try a Linux console with CONFIG_FB, or drop --framebuffer)"
            ),
            FbError::PermissionDenied(p) => write!(
                f,
                "permission denied opening {p}; add your user to the 'video' group \
                 (sudo usermod -aG video $USER) or run on the console as root"
            ),
            FbError::Busy(p) => write!(f, "framebuffer device {p} is busy / already in use"),
            FbError::Open(e) => write!(f, "failed to open framebuffer device: {e}"),
            FbError::Ioctl(e) => write!(f, "framebuffer ioctl (screeninfo) failed: {e}"),
            FbError::Mmap(e) => write!(f, "failed to mmap framebuffer memory: {e}"),
            FbError::UnsupportedFormat { bits_per_pixel } => write!(
                f,
                "unsupported framebuffer depth {bits_per_pixel}bpp; only 16 and 32 bits per \
                 pixel are supported"
            ),
        }
    }
}

impl std::error::Error for FbError {}

/// Classify an `open(2)` error into the actionable `FbError` variants.
fn classify_open_error(path: &str, e: io::Error) -> FbError {
    match e.kind() {
        io::ErrorKind::NotFound => FbError::NotFound(path.to_string()),
        io::ErrorKind::PermissionDenied => FbError::PermissionDenied(path.to_string()),
        _ => match e.raw_os_error() {
            Some(libc::EBUSY) => FbError::Busy(path.to_string()),
            _ => FbError::Open(e),
        },
    }
}

/// Derive the target `PixelFormat` from a `fb_var_screeninfo`. Pure (no I/O), so
/// it is unit-tested against synthetic screeninfo values.
fn format_from_vinfo(vinfo: &FbVarScreeninfo) -> Result<PixelFormat, FbError> {
    let bytes_per_pixel = match vinfo.bits_per_pixel {
        32 => 4,
        16 => 2,
        other => {
            return Err(FbError::UnsupportedFormat {
                bits_per_pixel: other,
            })
        }
    };
    Ok(PixelFormat {
        bytes_per_pixel,
        red: Channel {
            offset: vinfo.red.offset,
            length: vinfo.red.length,
        },
        green: Channel {
            offset: vinfo.green.offset,
            length: vinfo.green.length,
        },
        blue: Channel {
            offset: vinfo.blue.offset,
            length: vinfo.blue.length,
        },
    })
}

/// Convert a BGRA8888 source raster and blit the `damage` region into a packed
/// destination buffer with `dst_stride` bytes per row and `dst` geometry
/// `dst_size`. Pure (operates on plain slices) so the conversion + clipping math
/// is fully unit-testable without a real device.
///
/// `src` is BGRA8888 (byte order B, G, R, A) of dimensions `src_size`. The
/// damage rect is clipped to both the source and destination bounds.
pub fn blit_bgra_into(
    dst: &mut [u8],
    dst_stride: usize,
    dst_size: Size,
    fmt: &PixelFormat,
    src: &[u8],
    src_size: Size,
    damage: Rect,
) {
    let dst_w = dst_size.width as usize;
    let dst_h = dst_size.height as usize;
    let src_w = src_size.width as usize;
    let src_h = src_size.height as usize;
    let bpp = fmt.bytes_per_pixel;

    // Clip the damage rect to a non-negative origin, then to both rasters.
    let dx0 = damage.origin.x.max(0) as usize;
    let dy0 = damage.origin.y.max(0) as usize;
    let dx1 = (damage.origin.x.max(0) as usize + damage.size.width as usize)
        .min(dst_w)
        .min(src_w);
    let dy1 = (damage.origin.y.max(0) as usize + damage.size.height as usize)
        .min(dst_h)
        .min(src_h);

    for y in dy0..dy1 {
        let row = y * dst_stride;
        for x in dx0..dx1 {
            let s = (x + y * src_w) * 4;
            // Source is BGRA: byte 0=B, 1=G, 2=R.
            let b = src[s];
            let g = src[s + 1];
            let r = src[s + 2];
            let word = fmt.pack(r, g, b);
            let d = row + x * bpp;
            // Little-endian store of the low `bpp` bytes.
            for (i, byte) in dst[d..d + bpp].iter_mut().enumerate() {
                *byte = (word >> (8 * i)) as u8;
            }
        }
    }
}

/// An open, memory-mapped framebuffer device.
pub struct Framebuffer {
    path: String,
    _file: File,
    map: *mut u8,
    map_len: usize,
    stride: usize,
    size: Size,
    format: PixelFormat,
}

// The mmap pointer is owned exclusively by this struct and only touched on the
// render thread; presenting frames takes `&mut self`.
unsafe impl Send for Framebuffer {}

impl Framebuffer {
    /// Open `path`, query geometry/format, and map the framebuffer memory.
    pub fn open(path: &str) -> Result<Framebuffer, FbError> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(path)
            .map_err(|e| classify_open_error(path, e))?;
        let fd = file.as_raw_fd();

        let mut vinfo = unsafe { std::mem::zeroed::<FbVarScreeninfo>() };
        let mut finfo = unsafe { std::mem::zeroed::<FbFixScreeninfo>() };
        // SAFETY: fd is a valid open framebuffer; the structs match the kernel
        // UAPI layout and are fully owned here.
        if unsafe { libc::ioctl(fd, FBIOGET_VSCREENINFO, &mut vinfo) } != 0 {
            return Err(FbError::Ioctl(io::Error::last_os_error()));
        }
        if unsafe { libc::ioctl(fd, FBIOGET_FSCREENINFO, &mut finfo) } != 0 {
            return Err(FbError::Ioctl(io::Error::last_os_error()));
        }

        let format = format_from_vinfo(&vinfo)?;
        let stride = finfo.line_length as usize;
        let map_len = if finfo.smem_len != 0 {
            finfo.smem_len as usize
        } else {
            stride * vinfo.yres as usize
        };

        // SAFETY: mapping the device's framebuffer memory for read/write.
        let map = unsafe {
            libc::mmap(
                ptr::null_mut(),
                map_len,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                fd,
                0,
            )
        };
        if map == libc::MAP_FAILED {
            return Err(FbError::Mmap(io::Error::last_os_error()));
        }

        Ok(Framebuffer {
            path: path.to_string(),
            _file: file,
            map: map as *mut u8,
            map_len,
            stride,
            size: Size::new(vinfo.xres, vinfo.yres),
            format,
        })
    }

    /// Device resolution in pixels — the browser viewport should match this.
    pub fn size(&self) -> Size {
        self.size
    }

    /// Device pixel format.
    pub fn format(&self) -> PixelFormat {
        self.format
    }

    pub fn path(&self) -> &str {
        &self.path
    }

    /// Convert a BGRA8888 frame and blit the damage region to the device.
    pub fn present(&mut self, src_bgra: &[u8], src_size: Size, damage: Rect) {
        // SAFETY: `map`/`map_len` came from a successful mmap and outlive this
        // borrow; `&mut self` guarantees exclusive access to the mapping.
        let dst = unsafe { slice::from_raw_parts_mut(self.map, self.map_len) };
        blit_bgra_into(
            dst,
            self.stride,
            self.size,
            &self.format,
            src_bgra,
            src_size,
            damage,
        );
    }
}

impl Drop for Framebuffer {
    fn drop(&mut self) {
        if !self.map.is_null() {
            // SAFETY: unmapping exactly what we mapped.
            unsafe {
                libc::munmap(self.map as *mut libc::c_void, self.map_len);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn xrgb8888() -> PixelFormat {
        // 32bpp XRGB: B@0, G@8, R@16, each 8 bits.
        PixelFormat {
            bytes_per_pixel: 4,
            red: Channel {
                offset: 16,
                length: 8,
            },
            green: Channel {
                offset: 8,
                length: 8,
            },
            blue: Channel {
                offset: 0,
                length: 8,
            },
        }
    }

    fn rgb565() -> PixelFormat {
        // 16bpp RGB565: R@11(5), G@5(6), B@0(5).
        PixelFormat {
            bytes_per_pixel: 2,
            red: Channel {
                offset: 11,
                length: 5,
            },
            green: Channel {
                offset: 5,
                length: 6,
            },
            blue: Channel {
                offset: 0,
                length: 5,
            },
        }
    }

    #[test]
    fn pack_xrgb8888_roundtrips_full_channels() {
        let f = xrgb8888();
        // r=0x12 g=0x34 b=0x56 -> 0x00123456
        assert_eq!(f.pack(0x12, 0x34, 0x56), 0x0012_3456);
        assert_eq!(f.pack(0xFF, 0x00, 0x00), 0x00FF_0000);
        assert_eq!(f.pack(0x00, 0x00, 0xFF), 0x0000_00FF);
    }

    #[test]
    fn pack_rgb565_truncates_channels() {
        let f = rgb565();
        // White: R=0x1F, G=0x3F, B=0x1F -> 0xFFFF
        assert_eq!(f.pack(0xFF, 0xFF, 0xFF), 0xFFFF);
        // Pure red 0xFF -> top 5 bits = 0x1F at offset 11 -> 0xF800
        assert_eq!(f.pack(0xFF, 0x00, 0x00), 0xF800);
        // Pure green 0xFF -> top 6 bits = 0x3F at offset 5 -> 0x07E0
        assert_eq!(f.pack(0x00, 0xFF, 0x00), 0x07E0);
        // Pure blue 0xFF -> top 5 bits = 0x1F at offset 0 -> 0x001F
        assert_eq!(f.pack(0x00, 0x00, 0xFF), 0x001F);
    }

    #[test]
    fn blit_full_frame_32bpp() {
        let f = xrgb8888();
        // 2x2 source, BGRA. Pixel order B,G,R,A.
        // (0,0) red, (1,0) green, (0,1) blue, (1,1) white
        let src: Vec<u8> = vec![
            0x00, 0x00, 0xFF, 0xFF, // red
            0x00, 0xFF, 0x00, 0xFF, // green
            0xFF, 0x00, 0x00, 0xFF, // blue
            0xFF, 0xFF, 0xFF, 0xFF, // white
        ];
        let size = Size::new(2, 2);
        let stride = 2 * 4; // no padding
        let mut dst = vec![0u8; stride * 2];
        blit_bgra_into(
            &mut dst,
            stride,
            size,
            &f,
            &src,
            size,
            Rect::new(0, 0, 2, 2),
        );

        let word = |x: usize, y: usize| {
            let d = y * stride + x * 4;
            u32::from_le_bytes([dst[d], dst[d + 1], dst[d + 2], dst[d + 3]])
        };
        assert_eq!(word(0, 0), 0x00FF_0000); // red
        assert_eq!(word(1, 0), 0x0000_FF00); // green
        assert_eq!(word(0, 1), 0x0000_00FF); // blue
        assert_eq!(word(1, 1), 0x00FF_FFFF); // white
    }

    #[test]
    fn blit_honors_stride_padding() {
        let f = xrgb8888();
        // 1x2 source, but device row stride is 4 px worth of bytes (padding).
        let src: Vec<u8> = vec![
            0x00, 0x00, 0xFF, 0xFF, // (0,0) red
            0xFF, 0x00, 0x00, 0xFF, // (0,1) blue
        ];
        let size = Size::new(1, 2);
        let stride = 4 * 4; // padded row
        let mut dst = vec![0u8; stride * 2];
        blit_bgra_into(
            &mut dst,
            stride,
            Size::new(1, 2),
            &f,
            &src,
            size,
            Rect::new(0, 0, 1, 2),
        );

        let w0 = u32::from_le_bytes([dst[0], dst[1], dst[2], dst[3]]);
        let w1base = stride; // second row starts at `stride`
        let w1 = u32::from_le_bytes([
            dst[w1base],
            dst[w1base + 1],
            dst[w1base + 2],
            dst[w1base + 3],
        ]);
        assert_eq!(w0, 0x00FF_0000); // red on row 0
        assert_eq!(w1, 0x0000_00FF); // blue on row 1 (correct stride offset)
    }

    #[test]
    fn blit_clips_damage_to_bounds() {
        let f = xrgb8888();
        let src: Vec<u8> = vec![0x00, 0x00, 0xFF, 0xFF]; // 1x1 red
        let size = Size::new(1, 1);
        let stride = 1 * 4;
        let mut dst = vec![0u8; stride];
        // Damage rect larger than the raster must not panic and must clip.
        blit_bgra_into(
            &mut dst,
            stride,
            size,
            &f,
            &src,
            size,
            Rect::new(0, 0, 99, 99),
        );
        assert_eq!(
            u32::from_le_bytes([dst[0], dst[1], dst[2], dst[3]]),
            0x00FF_0000
        );
    }

    #[test]
    fn format_from_vinfo_rejects_unsupported_depth() {
        let mut v: FbVarScreeninfo = unsafe { std::mem::zeroed() };
        v.bits_per_pixel = 24;
        assert!(matches!(
            format_from_vinfo(&v),
            Err(FbError::UnsupportedFormat { bits_per_pixel: 24 })
        ));
        v.bits_per_pixel = 32;
        v.red = FbBitfield {
            offset: 16,
            length: 8,
            msb_right: 0,
        };
        v.green = FbBitfield {
            offset: 8,
            length: 8,
            msb_right: 0,
        };
        v.blue = FbBitfield {
            offset: 0,
            length: 8,
            msb_right: 0,
        };
        let f = format_from_vinfo(&v).unwrap();
        assert_eq!(f.bytes_per_pixel, 4);
        assert_eq!(f.pack(0x12, 0x34, 0x56), 0x0012_3456);
    }
}
