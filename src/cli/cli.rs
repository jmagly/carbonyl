use std::{env, ffi::OsStr};

use super::{CommandLineProgram, DumpFrameFormat, DumpTextMode};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SixelMode {
    Off,
    Auto,
    On,
    Kitty,
    Iterm2,
}

impl SixelMode {
    pub fn is_forced(self) -> bool {
        matches!(self, Self::On | Self::Kitty | Self::Iterm2)
    }

    pub fn is_auto(self) -> bool {
        matches!(self, Self::Auto)
    }
}

#[derive(Clone, Debug)]
pub struct CommandLine {
    pub args: Vec<String>,
    pub fps: f32,
    pub zoom: f32,
    pub debug: bool,
    pub bitmap: bool,
    pub program: CommandLineProgram,
    pub shell_mode: bool,
    /// Live terminal image output backend policy (#241). Forced image modes
    /// emit compositor frames as terminal images instead of using the default
    /// Unicode quadrant renderer. Auto mode keeps the quadrant renderer as
    /// fallback until DA1 reports sixel support; terminal-image auto first
    /// checks well-known kitty/iTerm2 environment markers. Set via
    /// `--sixel[=auto|on|off]`, `--terminal-image=...`, or env vars.
    pub sixel_mode: SixelMode,
    /// Optional consumer-provided CSS viewport override as (width, height).
    /// When set, Chromium lays out against this viewport regardless of
    /// terminal cell count, and the terminal samples a view onto the
    /// resulting physical raster. When unset, falls back to the legacy
    /// cells-derived viewport. Set via `--viewport=WIDTHxHEIGHT`.
    pub viewport: Option<(u32, u32)>,
    /// Number of terminal rows the URL/navigation chrome occupies.
    /// Defaults to 1 (legacy single-row chrome). Larger values stack the
    /// chrome buttons and URL text across multiple rows, restoring
    /// legibility on large terminals (e.g. 360x100) where a single row
    /// is ~10-12px tall and the chrome smears. Set via `--chrome-rows=N`.
    pub chrome_rows: u32,
    /// Optional Linux framebuffer device for direct-to-`/dev/fb0` output (#125).
    /// `Some(path)` selects the framebuffer backend (full pixel resolution on a
    /// local TTY, no X11/Wayland); `None` keeps the default terminal renderer.
    /// Set via `--framebuffer[=PATH]` or `CARBONYL_FRAMEBUFFER[=PATH]`; an empty
    /// or missing value defaults to `/dev/fb0`.
    pub framebuffer: Option<String>,
    /// Optional CSS-viewport height override in pixels for full-page layout (#87).
    /// `--viewport=WxH` clips the page to `H` px tall — content below the fold is
    /// never laid out or rastered. `--page-height=N` overrides only the height,
    /// keeping the width from `--viewport` (if set) or the terminal-derived
    /// width, so Chromium lays out (and rasters) the page `N` px tall. The
    /// screenshot capture FFI (#3) then receives the full-page raster. The
    /// interactive terminal still samples the top-left window — this knob targets
    /// the automation / screenshot path. Set via `--page-height=N` or
    /// `CARBONYL_PAGE_HEIGHT=N`; `0`/malformed values are ignored.
    pub page_height: Option<u32>,
    /// Whether Tab / Shift+Tab should be forwarded to Chromium for focus
    /// traversal. Default is false so Tab stays out of the page unless the
    /// operator opts in with `--tab-focus` / `--enable-tab-nav` (#242).
    pub tab_focus: bool,
    /// Optional Basic Auth credential (`user:pass`) used to rewrite the first
    /// top-level HTTP(S) URL before spawning Chromium (#171). The credential is
    /// not forwarded as a Chromium switch.
    pub basic_auth: Option<String>,
    /// Optional headless download directory (#182). `--download-dir` is
    /// preserved as a Chromium switch; `CARBONYL_DOWNLOAD_DIR` appends that
    /// switch when the CLI did not specify one.
    pub download_dir: Option<String>,
    /// Optional non-GUI file picker response path (#208). `--file-dialog-path`
    /// is preserved as a Chromium switch; `CARBONYL_FILE_DIALOG_PATH` appends
    /// that switch when the CLI did not specify one.
    pub file_dialog_path: Option<String>,
}

pub enum EnvVar {
    Debug,
    Bitmap,
    ShellMode,
}

impl EnvVar {
    pub fn as_str(&self) -> &'static str {
        match self {
            EnvVar::Debug => "CARBONYL_ENV_DEBUG",
            EnvVar::Bitmap => "CARBONYL_ENV_BITMAP",
            EnvVar::ShellMode => "CARBONYL_ENV_SHELL_MODE",
        }
    }
}

impl AsRef<OsStr> for EnvVar {
    fn as_ref(&self) -> &OsStr {
        self.as_str().as_ref()
    }
}

impl CommandLine {
    pub fn parse() -> CommandLine {
        Self::parse_args(env::args().skip(1).collect())
    }

    /// Parse an explicit argument vector (everything after argv[0]).
    ///
    /// Split out from `parse()` so the Chromium-flag passthrough invariant
    /// (#188, upstream fathyb#148) is unit-testable without touching the
    /// process's real argv. Flags Carbonyl does not recognize fall through to
    /// the `_ => ()` arm below and are preserved verbatim in `args`, which
    /// `bridge.rs::main()` forwards to the in-process Chromium child — so
    /// e.g. `--proxy-server` / `--user-agent` reach Chromium's
    /// `base::CommandLine`. Carbonyl's own flags are consumed here *and* still
    /// forwarded (Chromium ignores switches it doesn't know, like `--fps`).
    fn parse_args(args: Vec<String>) -> CommandLine {
        let mut fps = 60.0;
        let mut zoom = 1.0;
        let mut debug = false;
        let mut bitmap = false;
        let mut shell_mode = false;
        let mut sixel_mode = SixelMode::Off;
        let mut viewport: Option<(u32, u32)> = None;
        let mut chrome_rows: u32 = 1;
        let mut framebuffer: Option<String> = None;
        let mut page_height: Option<u32> = None;
        let mut tab_focus = false;
        let mut basic_auth: Option<String> = None;
        let mut download_dir: Option<String> = None;
        let mut file_dialog_path: Option<String> = None;
        let mut program = CommandLineProgram::Main;
        // Dump-mode scaffolding — collected during the loop and folded into
        // `program` after, so it composes with `--help` / `--version` /
        // `CARBONYL_DUMP_TEXT` env-var precedence. See #88.
        let mut dump_text_requested = false;
        let mut dump_text_mode = DumpTextMode::InnerText;
        let mut dump_frame_requested = false;
        let mut dump_frame_format = DumpFrameFormat::Png;
        let mut dump_idle_ms: u64 = 500;
        let mut dump_max_wait_ms: u64 = 30_000;

        for arg in &args {
            let split: Vec<&str> = arg.split("=").collect();
            let default = arg.as_str();
            let (key, value) = (split.first().unwrap_or(&default), split.get(1));

            macro_rules! set {
                ($var:ident, $enum:ident) => {{
                    $var = true;

                    env::set_var(EnvVar::$enum, "1");
                }};
            }

            macro_rules! set_f32 {
                ($var:ident = $expr:expr) => {{
                    if let Some(value) = value {
                        if let Ok(value) = value.parse::<f32>() {
                            $var = {
                                let $var = value;

                                $expr
                            };
                        }
                    }
                }};
            }

            match *key {
                "-f" | "--fps" => set_f32!(fps = fps),
                "-z" | "--zoom" => set_f32!(zoom = zoom / 100.0),
                "-d" | "--debug" => set!(debug, Debug),
                "-b" | "--bitmap" => set!(bitmap, Bitmap),
                "--sixel" => {
                    sixel_mode = value
                        .and_then(|value| parse_sixel_mode(value))
                        .unwrap_or(SixelMode::On)
                }
                "--terminal-image" | "--image-protocol" => {
                    if let Some(value) = value {
                        if let Some(mode) = parse_terminal_image_mode(value) {
                            sixel_mode = resolve_terminal_image_mode(mode);
                        }
                    }
                }
                "--viewport" => {
                    if let Some(value) = value {
                        if let Some((w, h)) = parse_viewport(value) {
                            viewport = Some((w, h));
                        }
                    }
                }
                "--chrome-rows" => {
                    if let Some(value) = value {
                        if let Ok(rows) = value.parse::<u32>() {
                            if rows > 0 {
                                chrome_rows = rows;
                            }
                        }
                    }
                }
                "--framebuffer" => framebuffer = Some(framebuffer_path(value.copied())),
                "--page-height" => {
                    if let Some(value) = value {
                        if let Some(h) = parse_page_height(value) {
                            page_height = Some(h);
                        }
                    }
                }
                "--tab-focus" | "--enable-tab-nav" => tab_focus = true,
                "--basic-auth" => {
                    if let Some(value) = basic_auth_value(arg) {
                        basic_auth = Some(value.to_string());
                    }
                }
                "--download-dir" => {
                    if let Some(value) = value {
                        if !value.is_empty() {
                            download_dir = Some(value.to_string());
                        }
                    }
                }
                "--file-dialog-path" => {
                    if let Some(value) = value {
                        if !value.is_empty() {
                            file_dialog_path = Some(value.to_string());
                        }
                    }
                }

                "--dump-text" => {
                    dump_text_requested = true;
                    if let Some(value) = value {
                        if let Some(mode) = parse_dump_text_mode(value) {
                            dump_text_mode = mode;
                        }
                    }
                }
                "--dump" | "--screenshot" => {
                    dump_frame_requested = true;
                    if let Some(value) = value {
                        if let Some(format) = parse_dump_frame_format(value) {
                            dump_frame_format = format;
                        }
                    }
                }
                "--idle" => {
                    if let Some(value) = value {
                        if let Ok(ms) = value.parse::<u64>() {
                            dump_idle_ms = ms;
                        }
                    }
                }
                "--max-wait" => {
                    if let Some(value) = value {
                        if let Ok(ms) = value.parse::<u64>() {
                            if ms > 0 {
                                dump_max_wait_ms = ms;
                            }
                        }
                    }
                }

                "-h" | "--help" => program = CommandLineProgram::Help,
                "-v" | "--version" => program = CommandLineProgram::Version,
                _ => (),
            }
        }

        if viewport.is_none() {
            if let Ok(value) = env::var("CARBONYL_VIEWPORT") {
                viewport = parse_viewport(&value);
            }
        }

        if chrome_rows == 1 {
            if let Ok(value) = env::var("CARBONYL_CHROME_ROWS") {
                if let Ok(rows) = value.parse::<u32>() {
                    if rows > 0 {
                        chrome_rows = rows;
                    }
                }
            }
        }

        if framebuffer.is_none() {
            if let Ok(value) = env::var("CARBONYL_FRAMEBUFFER") {
                framebuffer = Some(framebuffer_path(Some(value.as_str())));
            }
        }

        if page_height.is_none() {
            if let Ok(value) = env::var("CARBONYL_PAGE_HEIGHT") {
                page_height = parse_page_height(&value);
            }
        }

        if let Ok(value) = env::var("CARBONYL_TAB_FOCUS") {
            tab_focus = parse_bool_env(&value);
        }

        if basic_auth.is_none() {
            if let Ok(value) = env::var("CARBONYL_BASIC_AUTH") {
                if valid_basic_auth(&value) {
                    basic_auth = Some(value);
                }
            }
        }

        if download_dir.is_none() {
            if let Ok(value) = env::var("CARBONYL_DOWNLOAD_DIR") {
                if !value.is_empty() {
                    download_dir = Some(value);
                }
            }
        }

        if file_dialog_path.is_none() {
            if let Ok(value) = env::var("CARBONYL_FILE_DIALOG_PATH") {
                if !value.is_empty() {
                    file_dialog_path = Some(value);
                }
            }
        }

        let args = apply_file_dialog_path(
            apply_download_dir(apply_basic_auth(args, basic_auth.as_deref()), &download_dir),
            &file_dialog_path,
        );

        if !dump_text_requested {
            if let Ok(value) = env::var("CARBONYL_DUMP_TEXT") {
                // Empty value, "1", or an unrecognized mode keeps the default
                // InnerText. Anything we can parse overrides.
                dump_text_requested = true;
                if !value.is_empty() && value != "1" {
                    if let Some(mode) = parse_dump_text_mode(&value) {
                        dump_text_mode = mode;
                    }
                }
            }
        }

        if let Ok(value) = env::var("CARBONYL_DUMP_IDLE_MS") {
            if let Ok(ms) = value.parse::<u64>() {
                dump_idle_ms = ms;
            }
        }

        if let Ok(value) = env::var("CARBONYL_DUMP_MAX_WAIT_MS") {
            if let Ok(ms) = value.parse::<u64>() {
                if ms > 0 {
                    dump_max_wait_ms = ms;
                }
            }
        }

        if !dump_frame_requested {
            if let Ok(value) = env::var("CARBONYL_DUMP_FRAME") {
                dump_frame_requested = parse_bool_env(&value);
                if !value.is_empty() && value != "1" {
                    if let Some(format) = parse_dump_frame_format(&value) {
                        dump_frame_requested = true;
                        dump_frame_format = format;
                    }
                }
            }
        }

        // --dump-text wins over Main but loses to --help / --version so the
        // operator can still ask "what does --dump-text do?" without firing
        // the dump path.
        if dump_text_requested && matches!(program, CommandLineProgram::Main) {
            program = CommandLineProgram::DumpText {
                mode: dump_text_mode,
                idle_ms: dump_idle_ms,
                max_wait_ms: dump_max_wait_ms,
            };
        } else if dump_frame_requested && matches!(program, CommandLineProgram::Main) {
            program = CommandLineProgram::DumpFrame {
                format: dump_frame_format,
                idle_ms: dump_idle_ms,
                max_wait_ms: dump_max_wait_ms,
            };
        }

        if env::var(EnvVar::Debug).is_ok() {
            debug = true;
        }

        if env::var(EnvVar::Bitmap).is_ok() {
            bitmap = true;
        }

        if env::var(EnvVar::ShellMode).is_ok() {
            shell_mode = true;
        }

        if let Ok(value) = env::var("CARBONYL_SIXEL") {
            sixel_mode = parse_sixel_mode(&value).unwrap_or_else(|| {
                if parse_bool_env(&value) {
                    SixelMode::On
                } else {
                    SixelMode::Off
                }
            });
        }
        if let Ok(value) = env::var("CARBONYL_TERMINAL_IMAGE") {
            if let Some(mode) = parse_terminal_image_mode(&value) {
                sixel_mode = resolve_terminal_image_mode(mode);
            }
        }

        CommandLine {
            args,
            fps,
            zoom,
            debug,
            bitmap,
            program,
            shell_mode,
            sixel_mode,
            viewport,
            chrome_rows,
            framebuffer,
            page_height,
            tab_focus,
            basic_auth,
            download_dir,
            file_dialog_path,
        }
    }
}

fn basic_auth_value(arg: &str) -> Option<&str> {
    let value = arg.strip_prefix("--basic-auth=")?;
    valid_basic_auth(value).then_some(value)
}

fn valid_basic_auth(value: &str) -> bool {
    match value.split_once(':') {
        Some((user, pass)) => !user.is_empty() && !pass.is_empty(),
        None => false,
    }
}

fn apply_basic_auth(args: Vec<String>, credential: Option<&str>) -> Vec<String> {
    let Some(credential) = credential else {
        return args;
    };

    let mut rewritten = false;
    args.into_iter()
        .filter_map(|arg| {
            if arg == "--basic-auth" || arg.starts_with("--basic-auth=") {
                return None;
            }

            if !rewritten && !arg.starts_with('-') {
                rewritten = true;
                return Some(embed_basic_auth(&arg, credential).unwrap_or(arg));
            }

            Some(arg)
        })
        .collect()
}

fn embed_basic_auth(url: &str, credential: &str) -> Option<String> {
    let (scheme, rest) = url
        .strip_prefix("https://")
        .map(|rest| ("https://", rest))
        .or_else(|| url.strip_prefix("http://").map(|rest| ("http://", rest)))?;

    let authority_end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let (authority, suffix) = rest.split_at(authority_end);
    if authority.is_empty() || authority.contains('@') {
        return None;
    }

    let (user, pass) = credential.split_once(':')?;
    Some(format!(
        "{scheme}{}:{}@{authority}{suffix}",
        percent_encode_userinfo(user),
        percent_encode_userinfo(pass)
    ))
}

fn percent_encode_userinfo(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                encoded.push(byte as char)
            }
            _ => encoded.push_str(&format!("%{byte:02X}")),
        }
    }
    encoded
}

fn apply_download_dir(mut args: Vec<String>, download_dir: &Option<String>) -> Vec<String> {
    let Some(download_dir) = download_dir else {
        return args;
    };

    if args
        .iter()
        .any(|arg| arg == "--download-dir" || arg.starts_with("--download-dir="))
    {
        return args;
    }

    args.insert(0, format!("--download-dir={download_dir}"));
    args
}

fn apply_file_dialog_path(mut args: Vec<String>, file_dialog_path: &Option<String>) -> Vec<String> {
    let Some(file_dialog_path) = file_dialog_path else {
        return args;
    };

    if args
        .iter()
        .any(|arg| arg == "--file-dialog-path" || arg.starts_with("--file-dialog-path="))
    {
        return args;
    }

    args.insert(0, format!("--file-dialog-path={file_dialog_path}"));
    args
}

/// Resolve the framebuffer device path from an optional `=VALUE`. An empty or
/// missing value defaults to `/dev/fb0`.
fn framebuffer_path(value: Option<&str>) -> String {
    match value {
        Some(v) if !v.is_empty() => v.to_string(),
        _ => "/dev/fb0".to_string(),
    }
}

/// Parse a positive pixel height for `--page-height` / `CARBONYL_PAGE_HEIGHT`
/// (#87). Returns None on malformed input or a zero height.
fn parse_page_height(value: &str) -> Option<u32> {
    match value.parse::<u32>() {
        Ok(h) if h > 0 => Some(h),
        _ => None,
    }
}

/// Parse "WIDTHxHEIGHT" (case-insensitive 'x') into positive `(u32, u32)`.
/// Returns None on malformed input or zero dimensions.
fn parse_viewport(value: &str) -> Option<(u32, u32)> {
    let (w, h) = value.split_once(['x', 'X'])?;
    let w: u32 = w.parse().ok()?;
    let h: u32 = h.parse().ok()?;
    if w == 0 || h == 0 {
        return None;
    }
    Some((w, h))
}

fn parse_bool_env(value: &str) -> bool {
    matches!(
        value.to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "on"
    )
}

/// Parse the `--dump-text=<mode>` value. Returns None on unrecognized input,
/// letting the caller keep whichever default was already in effect.
fn parse_dump_text_mode(value: &str) -> Option<DumpTextMode> {
    match value.to_ascii_lowercase().as_str() {
        "innertext" | "inner-text" => Some(DumpTextMode::InnerText),
        "accessibility" | "a11y" | "ax" => Some(DumpTextMode::Accessibility),
        "raw-dom" | "rawdom" | "dom" | "outerhtml" => Some(DumpTextMode::RawDom),
        _ => None,
    }
}

fn parse_sixel_mode(value: &str) -> Option<SixelMode> {
    match value.to_ascii_lowercase().as_str() {
        "" | "1" | "true" | "yes" | "on" | "force" | "forced" => Some(SixelMode::On),
        "0" | "false" | "no" | "off" | "disable" | "disabled" => Some(SixelMode::Off),
        "auto" | "detect" | "detected" => Some(SixelMode::Auto),
        _ => None,
    }
}

fn parse_terminal_image_mode(value: &str) -> Option<SixelMode> {
    match value.to_ascii_lowercase().as_str() {
        "" | "0" | "false" | "no" | "off" | "disable" | "disabled" => Some(SixelMode::Off),
        "1" | "true" | "yes" | "on" | "sixel" | "sixel-on" | "sixel-force" => Some(SixelMode::On),
        "auto" | "detect" | "detected" | "sixel-auto" | "sixel-detect" => Some(SixelMode::Auto),
        "kitty" | "kitty-graphics" => Some(SixelMode::Kitty),
        "iterm" | "iterm2" | "inline-image" => Some(SixelMode::Iterm2),
        _ => None,
    }
}

fn resolve_terminal_image_mode(mode: SixelMode) -> SixelMode {
    if mode != SixelMode::Auto {
        return mode;
    }
    detect_terminal_image_mode().unwrap_or(SixelMode::Auto)
}

fn detect_terminal_image_mode() -> Option<SixelMode> {
    if env_present("KITTY_WINDOW_ID") || env_equals_ignore_case("TERM", "kitty") {
        return Some(SixelMode::Kitty);
    }

    if env_present("ITERM_SESSION_ID") || env_equals_ignore_case("TERM_PROGRAM", "iTerm.app") {
        return Some(SixelMode::Iterm2);
    }

    None
}

fn env_present(name: &str) -> bool {
    env::var(name).is_ok_and(|value| !value.is_empty())
}

fn env_equals_ignore_case(name: &str, expected: &str) -> bool {
    env::var(name).is_ok_and(|value| value.eq_ignore_ascii_case(expected))
}

/// Parse the `--dump=<format>` / `--screenshot=<format>` value.
fn parse_dump_frame_format(value: &str) -> Option<DumpFrameFormat> {
    match value.to_ascii_lowercase().as_str() {
        "" | "1" | "png" | "image/png" => Some(DumpFrameFormat::Png),
        "sixel" | "image/sixel" => Some(DumpFrameFormat::Sixel),
        "kitty" | "kitty-graphics" | "image/kitty" => Some(DumpFrameFormat::Kitty),
        "iterm" | "iterm2" | "inline-image" | "image/iterm2" => Some(DumpFrameFormat::Iterm2),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn dump_text_mode_aliases() {
        assert_eq!(
            parse_dump_text_mode("innertext"),
            Some(DumpTextMode::InnerText)
        );
        assert_eq!(
            parse_dump_text_mode("INNER-TEXT"),
            Some(DumpTextMode::InnerText)
        );
        assert_eq!(
            parse_dump_text_mode("accessibility"),
            Some(DumpTextMode::Accessibility)
        );
        assert_eq!(
            parse_dump_text_mode("a11y"),
            Some(DumpTextMode::Accessibility)
        );
        assert_eq!(parse_dump_text_mode("raw-dom"), Some(DumpTextMode::RawDom));
        assert_eq!(
            parse_dump_text_mode("OuterHTML"),
            Some(DumpTextMode::RawDom)
        );
        assert_eq!(parse_dump_text_mode("nope"), None);
    }

    #[test]
    fn dump_frame_format_aliases() {
        assert_eq!(parse_dump_frame_format(""), Some(DumpFrameFormat::Png));
        assert_eq!(parse_dump_frame_format("png"), Some(DumpFrameFormat::Png));
        assert_eq!(
            parse_dump_frame_format("IMAGE/PNG"),
            Some(DumpFrameFormat::Png)
        );
        assert_eq!(
            parse_dump_frame_format("sixel"),
            Some(DumpFrameFormat::Sixel)
        );
        assert_eq!(
            parse_dump_frame_format("IMAGE/SIXEL"),
            Some(DumpFrameFormat::Sixel)
        );
        assert_eq!(
            parse_dump_frame_format("kitty-graphics"),
            Some(DumpFrameFormat::Kitty)
        );
        assert_eq!(
            parse_dump_frame_format("ITERM2"),
            Some(DumpFrameFormat::Iterm2)
        );
        assert_eq!(parse_dump_frame_format("jpeg"), None);
    }

    #[test]
    fn dump_frame_cli_selects_program() {
        let original = std::env::var("CARBONYL_DUMP_FRAME").ok();
        std::env::remove_var("CARBONYL_DUMP_FRAME");

        let cmd = CommandLine::parse_args(vec!["--dump".to_string()]);
        assert!(matches!(
            cmd.program,
            CommandLineProgram::DumpFrame {
                format: DumpFrameFormat::Png,
                idle_ms: 500,
                max_wait_ms: 30_000
            }
        ));

        let cmd = CommandLine::parse_args(vec![
            "--screenshot=kitty".to_string(),
            "--idle=750".to_string(),
            "--max-wait=9000".to_string(),
        ]);
        assert!(matches!(
            cmd.program,
            CommandLineProgram::DumpFrame {
                format: DumpFrameFormat::Kitty,
                idle_ms: 750,
                max_wait_ms: 9000
            }
        ));

        if let Some(value) = original {
            std::env::set_var("CARBONYL_DUMP_FRAME", value);
        }
    }

    #[test]
    fn dump_text_takes_precedence_over_dump_frame() {
        let cmd = CommandLine::parse_args(vec!["--dump".to_string(), "--dump-text".to_string()]);
        assert!(matches!(
            cmd.program,
            CommandLineProgram::DumpText {
                mode: DumpTextMode::InnerText,
                ..
            }
        ));
    }

    #[test]
    fn viewport_parsing() {
        assert_eq!(parse_viewport("1280x800"), Some((1280, 800)));
        assert_eq!(parse_viewport("1280X800"), Some((1280, 800)));
        assert_eq!(parse_viewport("0x800"), None);
        assert_eq!(parse_viewport("abcxdef"), None);
    }

    #[test]
    fn framebuffer_path_defaults() {
        assert_eq!(framebuffer_path(None), "/dev/fb0");
        assert_eq!(framebuffer_path(Some("")), "/dev/fb0");
        assert_eq!(framebuffer_path(Some("/dev/fb1")), "/dev/fb1");
    }

    #[test]
    fn page_height_parsing() {
        assert_eq!(parse_page_height("4000"), Some(4000));
        assert_eq!(parse_page_height("1"), Some(1));
        assert_eq!(parse_page_height("0"), None);
        assert_eq!(parse_page_height(""), None);
        assert_eq!(parse_page_height("-1"), None);
        assert_eq!(parse_page_height("1280x800"), None);
        assert_eq!(parse_page_height("abc"), None);
    }

    #[test]
    fn tab_focus_defaults_off_and_cli_enables_it() {
        let original = std::env::var("CARBONYL_TAB_FOCUS").ok();
        std::env::remove_var("CARBONYL_TAB_FOCUS");

        let cmd = CommandLine::parse_args(vec!["https://example.com".to_string()]);
        assert!(!cmd.tab_focus);

        let cmd = CommandLine::parse_args(vec!["--tab-focus".to_string()]);
        assert!(cmd.tab_focus);

        let cmd = CommandLine::parse_args(vec!["--enable-tab-nav".to_string()]);
        assert!(cmd.tab_focus);

        if let Some(value) = original {
            std::env::set_var("CARBONYL_TAB_FOCUS", value);
        }
    }

    #[test]
    fn sixel_defaults_off_and_cli_enables_it() {
        let _guard = ENV_LOCK.lock().unwrap();
        let original = std::env::var("CARBONYL_SIXEL").ok();
        std::env::remove_var("CARBONYL_SIXEL");

        let cmd = CommandLine::parse_args(vec!["https://example.com".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Off);

        let cmd = CommandLine::parse_args(vec!["--sixel".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::On);

        let cmd = CommandLine::parse_args(vec!["--sixel=auto".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Auto);

        let cmd = CommandLine::parse_args(vec!["--sixel=off".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Off);

        if let Some(value) = original {
            std::env::set_var("CARBONYL_SIXEL", value);
        }
    }

    #[test]
    fn sixel_env_accepts_auto_and_boolean_values() {
        let _guard = ENV_LOCK.lock().unwrap();
        let original = std::env::var("CARBONYL_SIXEL").ok();

        std::env::set_var("CARBONYL_SIXEL", "auto");
        let cmd = CommandLine::parse_args(vec!["https://example.com".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Auto);

        std::env::set_var("CARBONYL_SIXEL", "1");
        let cmd = CommandLine::parse_args(vec!["https://example.com".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::On);

        std::env::set_var("CARBONYL_SIXEL", "0");
        let cmd = CommandLine::parse_args(vec!["--sixel".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Off);

        match original {
            Some(value) => std::env::set_var("CARBONYL_SIXEL", value),
            None => std::env::remove_var("CARBONYL_SIXEL"),
        }
    }

    #[test]
    fn terminal_image_cli_enables_live_kitty_and_iterm2() {
        let _guard = ENV_LOCK.lock().unwrap();
        let original = std::env::var("CARBONYL_TERMINAL_IMAGE").ok();
        let original_kitty = std::env::var("KITTY_WINDOW_ID").ok();
        let original_iterm = std::env::var("ITERM_SESSION_ID").ok();
        let original_term = std::env::var("TERM").ok();
        let original_term_program = std::env::var("TERM_PROGRAM").ok();
        std::env::remove_var("CARBONYL_TERMINAL_IMAGE");
        std::env::remove_var("KITTY_WINDOW_ID");
        std::env::remove_var("ITERM_SESSION_ID");
        std::env::remove_var("TERM");
        std::env::remove_var("TERM_PROGRAM");

        let cmd = CommandLine::parse_args(vec!["--terminal-image=kitty".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Kitty);

        let cmd = CommandLine::parse_args(vec!["--image-protocol=iterm2".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Iterm2);

        let cmd = CommandLine::parse_args(vec!["--terminal-image=sixel-auto".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Auto);

        match original {
            Some(value) => std::env::set_var("CARBONYL_TERMINAL_IMAGE", value),
            None => std::env::remove_var("CARBONYL_TERMINAL_IMAGE"),
        }
        restore_env("KITTY_WINDOW_ID", original_kitty);
        restore_env("ITERM_SESSION_ID", original_iterm);
        restore_env("TERM", original_term);
        restore_env("TERM_PROGRAM", original_term_program);
    }

    #[test]
    fn terminal_image_auto_detects_kitty_and_iterm2_envs() {
        let _guard = ENV_LOCK.lock().unwrap();
        let original_terminal = std::env::var("CARBONYL_TERMINAL_IMAGE").ok();
        let original_kitty = std::env::var("KITTY_WINDOW_ID").ok();
        let original_iterm = std::env::var("ITERM_SESSION_ID").ok();
        let original_term = std::env::var("TERM").ok();
        let original_term_program = std::env::var("TERM_PROGRAM").ok();

        std::env::remove_var("CARBONYL_TERMINAL_IMAGE");
        std::env::remove_var("KITTY_WINDOW_ID");
        std::env::remove_var("ITERM_SESSION_ID");
        std::env::remove_var("TERM");
        std::env::remove_var("TERM_PROGRAM");

        let cmd = CommandLine::parse_args(vec!["--terminal-image=auto".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Auto);

        std::env::set_var("KITTY_WINDOW_ID", "1");
        let cmd = CommandLine::parse_args(vec!["--terminal-image=auto".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Kitty);

        std::env::remove_var("KITTY_WINDOW_ID");
        std::env::set_var("TERM_PROGRAM", "iTerm.app");
        let cmd = CommandLine::parse_args(vec!["--terminal-image=auto".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Iterm2);

        std::env::set_var("CARBONYL_TERMINAL_IMAGE", "auto");
        let cmd = CommandLine::parse_args(vec!["https://example.com".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Iterm2);

        restore_env("CARBONYL_TERMINAL_IMAGE", original_terminal);
        restore_env("KITTY_WINDOW_ID", original_kitty);
        restore_env("ITERM_SESSION_ID", original_iterm);
        restore_env("TERM", original_term);
        restore_env("TERM_PROGRAM", original_term_program);
    }

    #[test]
    fn terminal_image_env_overrides_legacy_sixel_env() {
        let _guard = ENV_LOCK.lock().unwrap();
        let original_terminal = std::env::var("CARBONYL_TERMINAL_IMAGE").ok();
        let original_sixel = std::env::var("CARBONYL_SIXEL").ok();

        std::env::set_var("CARBONYL_SIXEL", "1");
        std::env::set_var("CARBONYL_TERMINAL_IMAGE", "kitty");
        let cmd = CommandLine::parse_args(vec!["https://example.com".to_string()]);
        assert_eq!(cmd.sixel_mode, SixelMode::Kitty);

        match original_terminal {
            Some(value) => std::env::set_var("CARBONYL_TERMINAL_IMAGE", value),
            None => std::env::remove_var("CARBONYL_TERMINAL_IMAGE"),
        }
        match original_sixel {
            Some(value) => std::env::set_var("CARBONYL_SIXEL", value),
            None => std::env::remove_var("CARBONYL_SIXEL"),
        }
    }

    fn restore_env(name: &str, value: Option<String>) {
        match value {
            Some(value) => std::env::set_var(name, value),
            None => std::env::remove_var(name),
        }
    }

    #[test]
    fn basic_auth_rewrites_first_http_url_and_consumes_flag() {
        let argv = vec![
            "--basic-auth=user:pass".to_string(),
            "--user-agent=Custom UA 1.0".to_string(),
            "https://example.com/path?q=1".to_string(),
        ];
        let cmd = CommandLine::parse_args(argv);

        assert_eq!(cmd.basic_auth.as_deref(), Some("user:pass"));
        assert_eq!(
            cmd.args,
            vec![
                "--user-agent=Custom UA 1.0".to_string(),
                "https://user:pass@example.com/path?q=1".to_string()
            ]
        );
    }

    #[test]
    fn basic_auth_percent_encodes_userinfo() {
        let argv = vec![
            "--basic-auth=user name:p@ss:word".to_string(),
            "http://example.com".to_string(),
        ];
        let cmd = CommandLine::parse_args(argv);

        assert_eq!(
            cmd.args,
            vec!["http://user%20name:p%40ss%3Aword@example.com".to_string()]
        );
    }

    #[test]
    fn basic_auth_does_not_rewrite_existing_userinfo_or_non_http_urls() {
        let cmd = CommandLine::parse_args(vec![
            "--basic-auth=user:pass".to_string(),
            "https://already:there@example.com".to_string(),
        ]);
        assert_eq!(cmd.args, vec!["https://already:there@example.com"]);

        let cmd = CommandLine::parse_args(vec![
            "--basic-auth=user:pass".to_string(),
            "file:///tmp/page.html".to_string(),
        ]);
        assert_eq!(cmd.args, vec!["file:///tmp/page.html"]);
    }

    #[test]
    fn download_dir_cli_is_preserved_as_chromium_switch() {
        let cmd = CommandLine::parse_args(vec![
            "--download-dir=/tmp/carbonyl-downloads".to_string(),
            "https://example.com".to_string(),
        ]);

        assert_eq!(cmd.download_dir.as_deref(), Some("/tmp/carbonyl-downloads"));
        assert_eq!(
            cmd.args,
            vec![
                "--download-dir=/tmp/carbonyl-downloads".to_string(),
                "https://example.com".to_string()
            ]
        );
    }

    #[test]
    fn download_dir_helper_appends_switch_when_cli_absent() {
        let args = apply_download_dir(
            vec!["https://example.com".to_string()],
            &Some("/tmp/from-env".to_string()),
        );
        assert_eq!(
            args,
            vec![
                "--download-dir=/tmp/from-env".to_string(),
                "https://example.com".to_string()
            ]
        );
    }

    #[test]
    fn download_dir_helper_keeps_existing_cli_switch() {
        let args = apply_download_dir(
            vec![
                "--download-dir=/tmp/from-cli".to_string(),
                "https://example.com".to_string(),
            ],
            &Some("/tmp/from-env".to_string()),
        );
        assert_eq!(
            args,
            vec![
                "--download-dir=/tmp/from-cli".to_string(),
                "https://example.com".to_string()
            ]
        );
    }

    #[test]
    fn file_dialog_path_cli_is_preserved_as_chromium_switch() {
        let cmd = CommandLine::parse_args(vec![
            "--file-dialog-path=/tmp/upload.txt".to_string(),
            "https://example.com".to_string(),
        ]);

        assert_eq!(cmd.file_dialog_path.as_deref(), Some("/tmp/upload.txt"));
        assert_eq!(
            cmd.args,
            vec![
                "--file-dialog-path=/tmp/upload.txt".to_string(),
                "https://example.com".to_string()
            ]
        );
    }

    #[test]
    fn file_dialog_path_helper_appends_switch_when_cli_absent() {
        let args = apply_file_dialog_path(
            vec!["https://example.com".to_string()],
            &Some("/tmp/from-env.txt".to_string()),
        );
        assert_eq!(
            args,
            vec![
                "--file-dialog-path=/tmp/from-env.txt".to_string(),
                "https://example.com".to_string()
            ]
        );
    }

    #[test]
    fn file_dialog_path_helper_keeps_existing_cli_switch() {
        let args = apply_file_dialog_path(
            vec![
                "--file-dialog-path=/tmp/from-cli.txt".to_string(),
                "https://example.com".to_string(),
            ],
            &Some("/tmp/from-env.txt".to_string()),
        );
        assert_eq!(
            args,
            vec![
                "--file-dialog-path=/tmp/from-cli.txt".to_string(),
                "https://example.com".to_string()
            ]
        );
    }

    #[test]
    fn bool_env_parsing() {
        assert!(parse_bool_env("1"));
        assert!(parse_bool_env("true"));
        assert!(parse_bool_env("YES"));
        assert!(parse_bool_env("on"));
        assert!(!parse_bool_env("0"));
        assert!(!parse_bool_env("false"));
        assert!(!parse_bool_env(""));
    }

    // Issue #188 / upstream fathyb#148: "Provide a way to pass flags to
    // chromium." Flags Carbonyl does not recognize (Chromium switches) must
    // survive verbatim in `args`, in order, so `bridge.rs::main()` can forward
    // them to the in-process Chromium child. This guards the passthrough
    // invariant against a future cleanup of the parse loop silently dropping
    // unknown flags. Asserting on `args` is env-independent: the field is the
    // input vector and is never mutated by the parser.
    #[test]
    fn chromium_flags_pass_through_verbatim() {
        let argv = vec![
            "--proxy-server=socks5://127.0.0.1:9050".to_string(),
            "--user-agent=Custom UA 1.0".to_string(),
            "--lang=fr-FR".to_string(),
            "--host-resolver-rules=MAP * 127.0.0.1".to_string(),
            "https://example.com".to_string(),
        ];
        let cmd = CommandLine::parse_args(argv.clone());

        // Every arg preserved verbatim and in order — the passthrough contract.
        assert_eq!(cmd.args, argv);
        // Unknown (Chromium) flags do not divert the program away from Main.
        assert!(matches!(cmd.program, CommandLineProgram::Main));
    }

    #[test]
    fn carbonyl_flags_are_consumed_yet_still_forwarded() {
        // A Carbonyl flag (`--fps`) is parsed into config AND still left on
        // `args` so it reaches Chromium too (which ignores unknown switches).
        // A Chromium flag in the same argv is untouched by the parser. #188.
        let argv = vec![
            "--fps=30".to_string(),
            "--proxy-server=http://proxy:8080".to_string(),
            "https://example.com".to_string(),
        ];
        let cmd = CommandLine::parse_args(argv.clone());

        assert_eq!(cmd.fps, 30.0); // consumed by Carbonyl
        assert_eq!(cmd.args, argv); // and still forwarded verbatim
    }

    #[test]
    fn chromium_flag_value_with_extra_equals_is_preserved() {
        // The parser splits on '=' and keeps only the first value segment, but
        // `args` retains the full original token — so a Chromium flag whose
        // value itself contains '=' is forwarded intact. #188.
        let argv = vec!["--proxy-server=https://u:p@host/?a=b&c=d".to_string()];
        let cmd = CommandLine::parse_args(argv.clone());

        assert_eq!(cmd.args, argv);
    }
}
