use std::{env, ffi::OsStr};

use super::{CommandLineProgram, DumpFrameFormat, DumpTextMode};

#[derive(Clone, Debug)]
pub struct CommandLine {
    pub args: Vec<String>,
    pub fps: f32,
    pub zoom: f32,
    pub debug: bool,
    pub bitmap: bool,
    pub program: CommandLineProgram,
    pub shell_mode: bool,
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
        let mut viewport: Option<(u32, u32)> = None;
        let mut chrome_rows: u32 = 1;
        let mut framebuffer: Option<String> = None;
        let mut page_height: Option<u32> = None;
        let mut tab_focus = false;
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

        CommandLine {
            args,
            fps,
            zoom,
            debug,
            bitmap,
            program,
            shell_mode,
            viewport,
            chrome_rows,
            framebuffer,
            page_height,
            tab_focus,
        }
    }
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

/// Parse the `--dump=<format>` / `--screenshot=<format>` value. Only PNG is
/// implemented today; aliases are accepted so the CLI has room to grow.
fn parse_dump_frame_format(value: &str) -> Option<DumpFrameFormat> {
    match value.to_ascii_lowercase().as_str() {
        "" | "1" | "png" | "image/png" => Some(DumpFrameFormat::Png),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
            "--screenshot=png".to_string(),
            "--idle=750".to_string(),
            "--max-wait=9000".to_string(),
        ]);
        assert!(matches!(
            cmd.program,
            CommandLineProgram::DumpFrame {
                format: DumpFrameFormat::Png,
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
