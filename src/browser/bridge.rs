// This file is the FFI boundary between libcarbonyl (Rust) and the
// Chromium C++ side. Every `pub extern "C" fn` here receives raw
// pointers from C++ and dereferences them — that is the whole point
// of the module. The clippy lint that insists these be `unsafe fn`
// would add an annotation that has no effect at the C ABI level
// (C callers don't see Rust's `unsafe` keyword) while forcing every
// C++ invocation to stay semantically the same. We suppress it here
// at the file level rather than decorating every function.
#![allow(clippy::not_unsafe_ptr_arg_deref)]

use std::collections::VecDeque;
use std::ffi::{CStr, CString};
use std::io::Write;
use std::process::{Command, Stdio};
use std::sync::{mpsc, Mutex};
use std::{env, io, thread};

use libc::{c_char, c_float, c_int, c_uchar, c_uint, c_void, size_t};

use crate::cli::{CommandLine, CommandLineProgram, EnvVar};
use crate::gfx::{Cast, Color, Point, Rect, Size};
use crate::output::{encode_png, Framebuffer, RenderThread, ScreenshotFormat, Window};
use crate::ui::navigation::NavigationAction;
use crate::{input, utils::log};

#[repr(C)]
#[derive(Copy, Clone)]
pub struct CSize {
    width: c_uint,
    height: c_uint,
}
#[repr(C)]
#[derive(Copy, Clone)]
pub struct CPoint {
    x: c_uint,
    y: c_uint,
}
#[repr(C)]
#[derive(Copy, Clone)]
pub struct CRect {
    origin: CPoint,
    size: CSize,
}
#[repr(C)]
#[derive(Copy, Clone)]
pub struct CColor {
    r: u8,
    g: u8,
    b: u8,
}
#[repr(C)]
#[derive(Copy, Clone)]
pub struct CText {
    text: *const c_char,
    rect: CRect,
    color: CColor,
}

#[repr(C)]
pub struct RendererBridge {
    cmd: CommandLine,
    window: Window,
    renderer: RenderThread,
    /// Optional additive framebuffer output sink (#125 cycle 2). When
    /// `--framebuffer`/`CARBONYL_FRAMEBUFFER` opened a device, every BGRA
    /// raster is also blitted here at full resolution while the terminal
    /// renderer keeps running — modeled on the X-mirror surface. `None` when
    /// the flag is unset or the device failed to open.
    framebuffer: Option<Framebuffer>,
    /// #3 screenshot capture. When armed via `carbonyl_set_screenshot_capture`,
    /// `draw_bitmap` retains a copy of the latest BGRA frame in `last_frame` so
    /// `carbonyl_capture_screenshot` can encode it on demand with no CDP
    /// round-trip. Disabled by default so standalone terminal sessions pay no
    /// per-frame copy cost — embedders (e.g. carbonyl-fleet) arm it explicitly.
    capture_enabled: bool,
    last_frame: Option<(Vec<u8>, Size)>,
}

unsafe impl Send for RendererBridge {}
unsafe impl Sync for RendererBridge {}

pub type RendererPtr = *const Mutex<RendererBridge>;

impl<T: Copy> From<CPoint> for Point<T>
where
    c_uint: Cast<T>,
{
    fn from(value: CPoint) -> Self {
        Point::new(value.x, value.y).cast()
    }
}
impl From<Size<c_uint>> for CSize {
    fn from(value: Size<c_uint>) -> Self {
        Self {
            width: value.width,
            height: value.height,
        }
    }
}
impl<T: Copy> From<CSize> for Size<T>
where
    c_uint: Cast<T>,
{
    fn from(value: CSize) -> Self {
        Size::new(value.width, value.height).cast()
    }
}
impl From<CColor> for Color {
    fn from(value: CColor) -> Self {
        Color::new(value.r, value.g, value.b)
    }
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct BrowserDelegate {
    shutdown: extern "C" fn(),
    refresh: extern "C" fn(),
    go_to: extern "C" fn(*const c_char),
    go_back: extern "C" fn(),
    go_forward: extern "C" fn(),
    scroll: extern "C" fn(c_int),
    key_press: extern "C" fn(c_char),
    mouse_up: extern "C" fn(c_uint, c_uint),
    mouse_down: extern "C" fn(c_uint, c_uint),
    mouse_move: extern "C" fn(c_uint, c_uint),
    post_task: extern "C" fn(extern "C" fn(*mut c_void), *mut c_void),
}

fn main() -> io::Result<Option<i32>> {
    let cmd = match CommandLineProgram::parse_or_run() {
        None => return Ok(Some(0)),
        Some(cmd) => cmd,
    };

    // --dump-text mode (issue #88): bypass the shell-mode fork. The
    // chromium process writes the extracted page text directly to its
    // own stdout via `carbonyl::DumpTextHandler` (browser-side C++,
    // installed by patch 0027). The handler reads `--dump-text`,
    // `--idle`, and `--max-wait` directly from chromium's
    // `base::CommandLine` — those switches are already on argv because
    // the user typed them, so no argv mutation is needed here.
    //
    // Returning Ok(None) makes carbonyl_bridge_main fall through to
    // chromium init in this same process — there is no child to spawn
    // and no terminal to set up; stdout already points at the user's
    // pipe.
    if matches!(cmd.program, CommandLineProgram::DumpText { .. }) {
        // Set CARBONYL_ENV_SHELL_MODE=1 in our env so chromium subprocesses
        // (zygote, gpu, renderer, ...) inherit it. Without this, each
        // subprocess re-enters Rust main() with the chromium-stripped argv
        // (no `--dump-text`) and falls through to the terminal-setup branch,
        // pumping ANSI escapes into the same stdout the dump handler is
        // about to write to. Setting shell_mode=true on the subprocess side
        // short-circuits `main()` to `Ok(None)` and lets chromium proceed
        // cleanly.
        env::set_var(EnvVar::ShellMode, "1");
        return Ok(None);
    }

    if cmd.shell_mode {
        return Ok(None);
    }

    let mut terminal = input::Terminal::setup();
    let mut command = Command::new(env::current_exe()?);

    if !cmd.bitmap {
        command
            .arg("--disable-threaded-scrolling")
            .arg("--disable-threaded-animation");
    }

    let output = command
        .args(cmd.args)
        .env(EnvVar::ShellMode, "1")
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::piped())
        .output()?;

    terminal.teardown();

    let code = output.status.code().unwrap_or(127);

    if code != 0 || cmd.debug {
        io::stderr().write_all(&output.stderr)?;
    }

    Ok(Some(code))
}

#[no_mangle]
pub extern "C" fn carbonyl_bridge_main() {
    if let Some(code) = main().unwrap() {
        std::process::exit(code)
    }
}

#[no_mangle]
pub extern "C" fn carbonyl_bridge_bitmap_mode() -> bool {
    CommandLine::parse().bitmap
}

#[no_mangle]
pub extern "C" fn carbonyl_bridge_get_dpi() -> c_float {
    Window::read().dpi
}

/// Open the Linux framebuffer when `--framebuffer`/`CARBONYL_FRAMEBUFFER` is set
/// (#125 cycle 2). The framebuffer is an *additive* output sink modeled on the
/// X-mirror (`CARBONYL_X_MIRROR`): on success it renders full-resolution frames
/// to the device while the terminal renderer keeps running. On failure it logs
/// the actionable, typed `FbError` and returns `None` — the terminal renderer is
/// unaffected, so a framebuffer-open problem never takes down the session.
///
/// On success the device resolution is recorded on the `Window` so the CSS
/// viewport tracks the real panel dimensions (unless an explicit `--viewport`
/// overrides it). See docs/framebuffer-backend.md.
fn open_framebuffer(cmd: &CommandLine, window: &mut Window) -> Option<Framebuffer> {
    let path = cmd.framebuffer.as_deref()?;

    match Framebuffer::open(path) {
        Ok(fb) => {
            let size = fb.size();
            log::debug!(
                "framebuffer enabled on {path}: {}x{} (additive with the terminal renderer)",
                size.width,
                size.height
            );
            window.fb_size = Some(size);
            Some(fb)
        }
        Err(err) => {
            log::warning!("framebuffer disabled: {err}; continuing with the terminal renderer");
            None
        }
    }
}

#[no_mangle]
pub extern "C" fn carbonyl_renderer_create() -> RendererPtr {
    let cmd = CommandLine::parse();
    let mut window = Window::read();
    // Open the framebuffer (if requested) before the first viewport
    // computation so the device resolution feeds the CSS viewport.
    let framebuffer = open_framebuffer(&cmd, &mut window);
    window.update();

    let bridge = RendererBridge {
        cmd,
        window,
        renderer: RenderThread::new(),
        framebuffer,
        capture_enabled: false,
        last_frame: None,
    };

    // NOTE: the network-event sink is registered lazily in `set_network_capture`
    // (the carbonyl-fleet entry point), NOT here. Calling
    // `carbonyl_set_network_callback` from this retained `#[no_mangle]` function
    // would keep an undefined reference to it *live* in libcarbonyl.so, breaking
    // the link of auxiliary binaries (e.g. v8_context_snapshot_generator) that
    // link libcarbonyl.so without the `:network` component under
    // `--no-allow-shlib-undefined`. Keeping the FFI reachable only from the
    // dormant `pub fn` below lets the linker dead-strip it — matching the
    // accessibility/JS handlers, which are likewise only reached from
    // carbonyl-fleet-facing `pub fn`s.

    Box::into_raw(Box::new(Mutex::new(bridge)))
}

#[no_mangle]
pub extern "C" fn carbonyl_renderer_start(bridge: RendererPtr) {
    // --dump-text (#88): the C++-side DumpTextHandler writes the
    // extracted page text directly to stdout. Enabling the terminal
    // renderer would interleave its ANSI escape sequences and chrome
    // bar into the same fd, corrupting the dump output. Skip the
    // render-thread spin-up in this mode.
    if matches!(
        CommandLine::parse().program,
        CommandLineProgram::DumpText { .. }
    ) {
        return;
    }

    {
        let bridge = unsafe { bridge.as_ref() };
        let mut bridge = bridge.unwrap().lock().unwrap();

        bridge.renderer.enable()
    }

    carbonyl_renderer_resize(bridge);
}

#[no_mangle]
pub extern "C" fn carbonyl_renderer_resize(bridge: RendererPtr) {
    let bridge = unsafe { bridge.as_ref() };
    let mut bridge = bridge.unwrap().lock().unwrap();
    let window = bridge.window.update();
    let cells = window.cells;

    log::debug!("resizing renderer, terminal window: {:?}", window);

    bridge
        .renderer
        .render(move |renderer| renderer.set_size(cells));
}

#[no_mangle]
pub extern "C" fn carbonyl_renderer_push_nav(
    bridge: RendererPtr,
    url: *const c_char,
    can_go_back: bool,
    can_go_forward: bool,
) {
    let (bridge, url) = unsafe { (bridge.as_ref(), CStr::from_ptr(url)) };
    let (mut bridge, url) = (bridge.unwrap().lock().unwrap(), url.to_owned());

    bridge.renderer.render(move |renderer| {
        renderer.push_nav(url.to_str().unwrap(), can_go_back, can_go_forward)
    });
}

#[no_mangle]
pub extern "C" fn carbonyl_renderer_set_title(bridge: RendererPtr, title: *const c_char) {
    let (bridge, title) = unsafe { (bridge.as_ref(), CStr::from_ptr(title)) };
    let (mut bridge, title) = (bridge.unwrap().lock().unwrap(), title.to_owned());

    bridge
        .renderer
        .render(move |renderer| renderer.set_title(title.to_str().unwrap()).unwrap());
}

#[no_mangle]
pub extern "C" fn carbonyl_renderer_draw_text(
    bridge: RendererPtr,
    text: *const CText,
    text_size: size_t,
) {
    let (bridge, text) = unsafe { (bridge.as_ref(), std::slice::from_raw_parts(text, text_size)) };
    let mut bridge = bridge.unwrap().lock().unwrap();
    let mut vec = text
        .iter()
        .map(|text| {
            let str = unsafe { CStr::from_ptr(text.text) };

            (
                str.to_str().unwrap().to_owned(),
                text.rect.origin.into(),
                text.rect.size.into(),
                text.color.into(),
            )
        })
        .collect::<Vec<(String, Point, Size, Color)>>();

    bridge.renderer.render(move |renderer| {
        renderer.clear_text();

        for (text, origin, size, color) in std::mem::take(&mut vec) {
            renderer.draw_text(&text, origin, size, color)
        }
    });
}

#[derive(Clone, Copy)]
struct CallbackData(*const c_void);

impl CallbackData {
    pub fn as_ptr(&self) -> *const c_void {
        self.0
    }
}

unsafe impl Send for CallbackData {}
unsafe impl Sync for CallbackData {}

#[no_mangle]
pub extern "C" fn carbonyl_renderer_draw_bitmap(
    bridge: RendererPtr,
    pixels: *const c_uchar,
    pixels_size: CSize,
    rect: CRect,
    callback: extern "C" fn(*const c_void),
    callback_data: *const c_void,
) {
    let length = (pixels_size.width * pixels_size.height * 4) as usize;
    let (bridge, pixels) = unsafe { (bridge.as_ref(), std::slice::from_raw_parts(pixels, length)) };
    let callback_data = CallbackData(callback_data);
    let mut bridge = bridge.unwrap().lock().unwrap();

    // #125 cycle 2: additive framebuffer sink. Blit the same BGRA raster to the
    // device at full resolution while the terminal renderer keeps running
    // (modeled on the X-mirror). No-op unless `--framebuffer` opened a device.
    // Runs synchronously here while `pixels` is valid and `bridge` is locked.
    if let Some(fb) = bridge.framebuffer.as_mut() {
        fb.present(
            pixels,
            pixels_size.into(),
            Rect {
                size: rect.size.into(),
                origin: rect.origin.into(),
            },
        );
    }

    // #3 screenshot capture: retain the latest full BGRA frame when armed so
    // carbonyl_capture_screenshot can encode it on demand. Gated on
    // capture_enabled — the per-frame copy is only paid when an embedder
    // actually wants screenshots.
    if bridge.capture_enabled {
        bridge.last_frame = Some((pixels.to_vec(), pixels_size.into()));
    }

    bridge.renderer.render(move |renderer| {
        renderer.draw_background(
            pixels,
            pixels_size.into(),
            Rect {
                size: rect.size.into(),
                origin: rect.origin.into(),
            },
        );

        callback(callback_data.as_ptr());
    });
}

/// Owned byte buffer handed across FFI (e.g. an encoded screenshot). The caller
/// MUST return it to `carbonyl_free_screenshot` to release it. An empty result
/// (capture not armed, no frame yet, or encode failure) is `{ null, 0, 0 }`.
#[repr(C)]
pub struct CBuffer {
    data: *mut c_uchar,
    len: size_t,
    cap: size_t,
}

impl CBuffer {
    fn empty() -> CBuffer {
        CBuffer {
            data: std::ptr::null_mut(),
            len: 0,
            cap: 0,
        }
    }

    fn from_vec(mut v: Vec<u8>) -> CBuffer {
        let buf = CBuffer {
            data: v.as_mut_ptr(),
            len: v.len(),
            cap: v.capacity(),
        };
        // Ownership transfers to the caller; reclaimed in carbonyl_free_screenshot.
        std::mem::forget(v);
        buf
    }
}

/// Arm or disarm screenshot capture (#3). While armed, `draw_bitmap` retains a
/// copy of the latest BGRA frame so `carbonyl_capture_screenshot` can encode it.
/// Disarming drops any retained frame so the memory isn't held.
#[no_mangle]
pub extern "C" fn carbonyl_set_screenshot_capture(bridge: RendererPtr, enabled: bool) {
    let bridge = unsafe { bridge.as_ref() };
    let mut bridge = bridge.unwrap().lock().unwrap();

    bridge.capture_enabled = enabled;
    if !enabled {
        bridge.last_frame = None;
    }
}

/// Encode the latest captured frame to an image and return it as an owned
/// `CBuffer` (#3). `format` is reserved for future formats (JPEG is deferred);
/// every value encodes PNG today, and `quality` is ignored for PNG. Returns an
/// empty buffer when capture is not armed, no frame has arrived yet, or encoding
/// fails. The caller owns the result and must pass it to
/// `carbonyl_free_screenshot`.
#[no_mangle]
pub extern "C" fn carbonyl_capture_screenshot(
    bridge: RendererPtr,
    format: *const c_char,
    _quality: u8,
) -> CBuffer {
    let bridge = unsafe { bridge.as_ref() };
    let bridge = bridge.unwrap().lock().unwrap();

    // Parse the requested format for forward-compatibility; PNG is the only
    // backend today, so the parsed value is intentionally unused.
    let _format = if format.is_null() {
        ScreenshotFormat::Png
    } else {
        let s = unsafe { CStr::from_ptr(format) };
        ScreenshotFormat::parse(s.to_str().unwrap_or("png"))
    };

    match &bridge.last_frame {
        Some((bgra, size)) => match encode_png(bgra, *size) {
            Some(png) => CBuffer::from_vec(png),
            None => CBuffer::empty(),
        },
        None => CBuffer::empty(),
    }
}

/// Release a `CBuffer` returned by `carbonyl_capture_screenshot`. Safe to call
/// on an empty buffer.
#[no_mangle]
pub extern "C" fn carbonyl_free_screenshot(buffer: CBuffer) {
    if !buffer.data.is_null() {
        // SAFETY: reconstruct exactly the Vec leaked by CBuffer::from_vec, so the
        // allocator frees the same (ptr, len, cap) it handed out.
        unsafe {
            drop(Vec::from_raw_parts(buffer.data, buffer.len, buffer.cap));
        }
    }
}

/// Return the CSS viewport size Chromium should lay out and raster against.
///
/// Two regimes:
///
/// * **Consumer-provided viewport** (`--viewport=WxH` or `CARBONYL_VIEWPORT=WxH`).
///   The returned size equals the requested viewport verbatim, and `dpi = 1.0`.
///   Chromium rasters at that exact physical size. The terminal samples a
///   `cells * (2, 4)` window of it; whatever doesn't fit is handled by the
///   consumer (scroll, pan, quadrant stitching).
///
/// * **Legacy (terminal-derived) viewport** — no `--viewport` set. The returned
///   size is `cells * scale` where `scale = (2, 4) / dpi`. This is what older
///   builds did; it lays Blink out against a CSS viewport whose size depends on
///   terminal cell count and is the source of the #37 "only upper-left visible"
///   report at small terminals. Kept for backward compatibility; new consumers
///   should provide an explicit viewport.
#[no_mangle]
pub extern "C" fn carbonyl_renderer_get_size(bridge: RendererPtr) -> CSize {
    let bridge = unsafe { bridge.as_ref() };
    let bridge = bridge.unwrap().lock().unwrap();

    log::debug!("terminal size: {:?}", bridge.window.browser);

    bridge.window.browser.into()
}

extern "C" fn post_task_handler(callback: *mut c_void) {
    let mut closure = unsafe { Box::from_raw(callback as *mut Box<dyn FnMut()>) };

    closure()
}

unsafe fn post_task<F>(handle: extern "C" fn(extern "C" fn(*mut c_void), *mut c_void), run: F)
where
    F: FnMut() + Send + 'static,
{
    let closure: *mut Box<dyn FnMut()> = Box::into_raw(Box::new(Box::new(run)));

    handle(post_task_handler, closure as *mut c_void);
}

/// Function called by the C++ code to listen for input events.
///
/// This will block so the calling code should start and own a dedicated thread.
/// It will panic if there is any error.
/// Translate one batch of input `Event`s into browser-delegate calls. Shared by
/// every input source so the bridge is source-agnostic: the stdin/terminal
/// `listen` thread and the framebuffer-mode `listen_evdev` thread (#125) both
/// funnel here. Serialized by the bridge `Mutex` regardless of source.
fn dispatch_input_events(
    bridge: &'static Mutex<RendererBridge>,
    delegate: BrowserDelegate,
    mut events: Vec<input::Event>,
) {
    use input::*;

    macro_rules! emit {
        ($event:ident($($args:expr),*) => $closure:expr) => {{
            let run = move || {
                (delegate.$event)($($args),*);

                $closure
            };

            unsafe { post_task(delegate.post_task, run) }
        }};
        ($event:ident($($args:expr),*)) => {{
            emit!($event($($args),*) => {})
        }};
    }

    bridge.lock().unwrap().renderer.render(move |renderer| {
        let get_scale = || bridge.lock().unwrap().window.scale;
        let scale = |col, row| {
            let scale = get_scale();

            scale
                .mul(((col as f32 + 0.5), (row as f32 - 0.5)))
                .floor()
                .cast()
                .into()
        };
        let dispatch = |action| {
            match action {
                NavigationAction::Ignore => (),
                NavigationAction::Forward => return true,
                NavigationAction::GoBack() => emit!(go_back()),
                NavigationAction::GoForward() => emit!(go_forward()),
                NavigationAction::Refresh() => emit!(refresh()),
                NavigationAction::GoTo(url) => {
                    let c_str = CString::new(url).unwrap();

                    emit!(go_to(c_str.as_ptr()))
                }
            };

            false
        };

        for event in std::mem::take(&mut events) {
            use Event::*;

            match event {
                Exit => (),
                Scroll { delta } => {
                    let scale = get_scale();

                    emit!(scroll((delta as f32 * scale.height) as c_int))
                }
                KeyPress { key } => {
                    if dispatch(renderer.keypress(&key).unwrap()) {
                        emit!(key_press(key.char as c_char))
                    }
                }
                MouseUp { col, row } => {
                    if dispatch(renderer.mouse_up((col as _, row as _).into()).unwrap()) {
                        let (width, height) = scale(col, row);

                        emit!(mouse_up(width, height))
                    }
                }
                MouseDown { col, row } => {
                    if dispatch(renderer.mouse_down((col as _, row as _).into()).unwrap()) {
                        let (width, height) = scale(col, row);

                        emit!(mouse_down(width, height))
                    }
                }
                MouseMove { col, row } => {
                    if dispatch(renderer.mouse_move((col as _, row as _).into()).unwrap()) {
                        let (width, height) = scale(col, row);

                        emit!(mouse_move(width, height))
                    }
                }
                Terminal(terminal) => match terminal {
                    TerminalEvent::Name(name) => log::debug!("terminal name: {name}"),
                    TerminalEvent::TrueColorSupported => renderer.enable_true_color(),
                },
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn carbonyl_renderer_listen(bridge: RendererPtr, delegate: *mut BrowserDelegate) {
    let bridge: &'static Mutex<RendererBridge> = unsafe { &*bridge };
    let delegate = unsafe { *delegate };

    // #125 cycle 2: in framebuffer mode there may be no PTY emitting terminal
    // escape sequences, so also read local input from evdev (/dev/input/event*).
    // Additive — the stdin listener below still runs, so input works whether the
    // session is a bare console or a controlling terminal/SSH. evdev failures
    // (no device / no permission) end this thread quietly and leave stdin input.
    if bridge.lock().unwrap().cmd.framebuffer.is_some() {
        thread::spawn(move || {
            if let Err(err) =
                input::listen_evdev(|events| dispatch_input_events(bridge, delegate, events))
            {
                log::debug!("evdev input unavailable: {err}");
            }
        });
    }

    thread::spawn(move || {
        input::listen(|events| dispatch_input_events(bridge, delegate, events)).unwrap();

        // Signal the browser to shut down, then wait for acknowledgement.
        let (tx, rx) = mpsc::channel();
        let run = move || {
            (delegate.shutdown)();
            tx.send(()).unwrap();
        };
        unsafe { post_task(delegate.post_task, run) };
        rx.recv().unwrap();

        // Shutdown rendering thread
        // if let Some(handle) = { bridge.lock().unwrap().renderer().stop() } {
        //     handle.join().unwrap()
        // }
    });
}

// ----- Accessibility Tree FFI (issue #4) ----------------------------------
//
// The C++ side lives in `carbonyl/src/browser/accessibility_handler.{cc,h}`
// (GN component `:accessibility`). The handler is installed as a
// process-wide singleton on the primary `WebContents` by chromium patch
// 0028, and `RequestAXTreeSnapshotWithinBrowserProcess()` is invoked
// synchronously inside `carbonyl_get_accessibility_tree()` — no IPC
// roundtrip, no callback plumbing on this side.
//
// Ownership: the C++ side allocates the returned C string with `new
// char[]`. We MUST release it via `carbonyl_free_string()` (also defined
// C++-side) — `libc::free` is wrong (mismatched allocator) and so is
// letting it leak. `get_accessibility_tree()` below handles this
// internally so callers receive an owned `String`.
//
// Thread-affinity: per the handler header, calls must occur on the
// browser UI thread. The socket-command code path that reaches this FFI
// (carbonyl-fleet#10) must `post_task` from the input/socket thread to
// the UI thread before invoking — see how the existing `BrowserDelegate`
// callbacks above are dispatched via `post_task` from the input thread.

extern "C" {
    fn carbonyl_get_accessibility_tree() -> *const c_char;
    fn carbonyl_free_string(ptr: *const c_char);
}

/// Returns the current accessibility tree of the primary WebContents as
/// a JSON `String`. On any failure path (AX mode not enabled, no
/// snapshot available, JSON serialization failure) returns the sentinel
/// JSON `{"error":"no_tree"}` — never panics, never returns `None`.
///
/// Must be called on the browser UI thread (see module-level note above
/// the FFI declarations).
pub fn get_accessibility_tree() -> String {
    // SAFETY: `carbonyl_get_accessibility_tree` is documented (in the
    // C++ header) to always return a non-null heap-allocated UTF-8 C
    // string. We immediately copy into an owned `String` and hand the
    // raw pointer back to `carbonyl_free_string`, so the pointer is
    // never read after free.
    unsafe {
        let raw = carbonyl_get_accessibility_tree();
        if raw.is_null() {
            // Defensive — should not happen given the C++ contract, but
            // surfacing the sentinel here is cheaper than panicking and
            // matches what the C++ side would have returned anyway.
            return String::from(r#"{"error":"no_tree"}"#);
        }
        let owned = CStr::from_ptr(raw).to_string_lossy().into_owned();
        carbonyl_free_string(raw);
        owned
    }
}

// JavaScript evaluation FFI (issue #5). Unlike the synchronous accessibility
// snapshot, JS eval round-trips to the renderer: the result is delivered to a
// C callback on the UI thread (see src/browser/javascript_handler.{h,cc}). We
// adapt that to an ergonomic `FnOnce(String)` via a boxed-closure trampoline,
// the same pattern as `post_task`. The JSON string handed to the callback is
// freed via `carbonyl_free_string` (reused from the accessibility FFI above).

extern "C" {
    /// Async. Schedules `script` on the primary main frame's isolated world;
    /// `callback(json, user_data)` fires exactly once on the UI thread with a
    /// `new char[]` JSON string the callee frees via `carbonyl_free_string`.
    /// On the no-WebContents / no-frame fast paths the callback is invoked
    /// synchronously (before return) with the error envelope.
    fn carbonyl_eval_javascript(
        script: *const c_char,
        callback: extern "C" fn(*const c_char, *mut c_void),
        user_data: *mut c_void,
    );
}

/// Trampoline handed to `carbonyl_eval_javascript`. Reconstructs the boxed
/// `FnOnce(String)` from `user_data`, copies the JSON into an owned `String`,
/// releases the C string, and invokes the closure exactly once. Runs on the
/// browser UI thread.
extern "C" fn eval_result_trampoline(json: *const c_char, user_data: *mut c_void) {
    // SAFETY: `user_data` is exactly the `Box<Box<dyn FnOnce(String) + Send>>`
    // leaked by `eval_javascript`, handed back unchanged by the C++ side and
    // invoked exactly once — so reconstructing and dropping it here is sound.
    let closure: Box<Box<dyn FnOnce(String) + Send>> =
        unsafe { Box::from_raw(user_data as *mut Box<dyn FnOnce(String) + Send>) };

    let result = unsafe {
        if json.is_null() {
            // Defensive — the C++ contract always passes a non-null envelope.
            String::from(r#"{"result":null,"error":"no_result"}"#)
        } else {
            let owned = CStr::from_ptr(json).to_string_lossy().into_owned();
            carbonyl_free_string(json);
            owned
        }
    };

    closure(result);
}

/// Evaluate `script` in the primary main frame's isolated world and deliver
/// the JSON-serialized result to `on_result`. The string is either the
/// serialized script value (e.g. `"\"hi\""`, `"42"`, `"{...}"`; a void result
/// serializes to `"null"`) or the error envelope
/// `{"result":null,"error":"<reason>"}` (`no_web_contents`, `no_main_frame`,
/// `serialization_failed`, or `invalid_script`).
///
/// `on_result` runs on the browser UI thread and is invoked exactly once.
/// Must be called on the browser UI thread (see the accessibility FFI note).
pub fn eval_javascript<F>(script: &str, on_result: F)
where
    F: FnOnce(String) + Send + 'static,
{
    let c_script = match CString::new(script) {
        Ok(s) => s,
        Err(_) => {
            // Interior NUL byte — cannot pass as a C string. Deliver the error
            // envelope directly (closure still invoked exactly once, no FFI
            // round-trip) rather than silently truncating the script.
            on_result(String::from(r#"{"result":null,"error":"invalid_script"}"#));
            return;
        }
    };

    let boxed: *mut Box<dyn FnOnce(String) + Send> = Box::into_raw(Box::new(Box::new(on_result)));

    // SAFETY: C++ copies the script synchronously into a std::u16string before
    // returning, so the local `c_script` lifetime is sufficient; `boxed` is
    // reclaimed exactly once by `eval_result_trampoline` on the UI thread.
    unsafe {
        carbonyl_eval_javascript(
            c_script.as_ptr(),
            eval_result_trampoline,
            boxed as *mut c_void,
        );
    }
}

// Network-event capture FFI (issue #6). The C++ NetworkHandler observes
// WebContentsObserver::ResourceLoadComplete and pushes one JSON object per
// completed resource to the trampoline below. The ring buffer lives here
// (Rust owns it, per the issue); retrieval/clear are exposed for the
// carbonyl-fleet socket layer (#11). Capture is opt-in — `set_network_capture`
// arms the C++ side, which early-returns (no serialization) while disarmed.

extern "C" {
    /// Register the per-event sink. Called once at startup with
    /// `network_event_trampoline`. See src/browser/network_handler.{h,cc}.
    fn carbonyl_set_network_callback(callback: extern "C" fn(*const c_char));

    /// Arm/disarm capture C++-side. While disarmed, ResourceLoadComplete does
    /// no work; arming is what makes the per-resource serialize happen.
    fn carbonyl_set_network_capture(enabled: bool);
}

/// Maximum buffered network events; oldest are evicted past this cap.
const NETWORK_LOG_CAP: usize = 1000;

/// Per-process ring buffer of network events, each a JSON object string from
/// the C++ side. `VecDeque::new` and `Mutex::new` are const, so this needs no
/// lazy initializer. Touched on the UI thread (trampoline) and the socket
/// thread (log/clear) — the Mutex serializes both.
static NETWORK_LOG: Mutex<VecDeque<String>> = Mutex::new(VecDeque::new());

/// Trampoline registered with `carbonyl_set_network_callback`. Copies the JSON
/// event into the ring buffer, evicting the oldest entry past the cap. Runs on
/// the browser UI thread (ResourceLoadComplete affinity). The pointer is valid
/// only for the duration of the call (C++ owns the backing `std::string`), so
/// we copy synchronously and never retain it.
extern "C" fn network_event_trampoline(json: *const c_char) {
    if json.is_null() {
        return;
    }
    // SAFETY: `json` is a non-null, NUL-terminated UTF-8 C string owned by the
    // C++ caller for the duration of this synchronous call; we copy and return.
    let event = unsafe { CStr::from_ptr(json).to_string_lossy().into_owned() };

    if let Ok(mut log) = NETWORK_LOG.lock() {
        if log.len() >= NETWORK_LOG_CAP {
            log.pop_front();
        }
        log.push_back(event);
    }
}

/// Arm or disarm network capture (#6). Disabled by default; the carbonyl-fleet
/// socket layer (#11) arms it on demand. Disarming stops new events but leaves
/// the buffer intact (use `network_clear` to flush).
///
/// The C++ sink is (re)registered here rather than at renderer creation so the
/// network FFI is reachable only from this dormant `pub fn` — letting the
/// linker dead-strip it in binaries that don't pull in the carbonyl-fleet
/// surface (see the note in `carbonyl_renderer_create`). Registration is
/// idempotent C++-side (it just stores the callback pointer).
pub fn set_network_capture(enabled: bool) {
    // SAFETY: `network_event_trampoline` is a plain `extern "C" fn` with static
    // lifetime; both FFIs are plain C-ABI setters writing to C++ statics.
    unsafe {
        carbonyl_set_network_callback(network_event_trampoline);
        carbonyl_set_network_capture(enabled);
    }
}

/// Return the buffered network events as a JSON array string (oldest first).
/// Each entry is already a serialized JSON object, so we join with commas
/// inside brackets rather than re-serializing.
pub fn network_log() -> String {
    let log = match NETWORK_LOG.lock() {
        Ok(log) => log,
        Err(_) => return String::from("[]"),
    };
    let mut out = String::with_capacity(log.iter().map(|e| e.len() + 1).sum::<usize>() + 2);
    out.push('[');
    for (i, entry) in log.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str(entry);
    }
    out.push(']');
    out
}

/// Flush the network ring buffer (#6 `network_clear`). After this, `network_log`
/// returns `[]` until new events arrive.
pub fn network_clear() {
    if let Ok(mut log) = NETWORK_LOG.lock() {
        log.clear();
    }
}
