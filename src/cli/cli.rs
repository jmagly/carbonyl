use std::{env, ffi::OsStr};

use super::{CommandLineProgram, DumpTextMode};

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
        let mut fps = 60.0;
        let mut zoom = 1.0;
        let mut debug = false;
        let mut bitmap = false;
        let mut shell_mode = false;
        let mut viewport: Option<(u32, u32)> = None;
        let mut chrome_rows: u32 = 1;
        let mut program = CommandLineProgram::Main;
        // --dump-text scaffolding — collected during the loop and folded into
        // `program` after, so it composes with `--help` / `--version` /
        // `CARBONYL_DUMP_TEXT` env-var precedence. See #88.
        let mut dump_text_requested = false;
        let mut dump_text_mode = DumpTextMode::InnerText;
        let mut dump_text_idle_ms: u64 = 500;
        let mut dump_text_max_wait_ms: u64 = 30_000;
        let args = env::args().skip(1).collect::<Vec<String>>();

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

                "--dump-text" => {
                    dump_text_requested = true;
                    if let Some(value) = value {
                        if let Some(mode) = parse_dump_text_mode(value) {
                            dump_text_mode = mode;
                        }
                    }
                }
                "--idle" => {
                    if let Some(value) = value {
                        if let Ok(ms) = value.parse::<u64>() {
                            dump_text_idle_ms = ms;
                        }
                    }
                }
                "--max-wait" => {
                    if let Some(value) = value {
                        if let Ok(ms) = value.parse::<u64>() {
                            if ms > 0 {
                                dump_text_max_wait_ms = ms;
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
                dump_text_idle_ms = ms;
            }
        }

        if let Ok(value) = env::var("CARBONYL_DUMP_MAX_WAIT_MS") {
            if let Ok(ms) = value.parse::<u64>() {
                if ms > 0 {
                    dump_text_max_wait_ms = ms;
                }
            }
        }

        // --dump-text wins over Main but loses to --help / --version so the
        // operator can still ask "what does --dump-text do?" without firing
        // the dump path.
        if dump_text_requested && matches!(program, CommandLineProgram::Main) {
            program = CommandLineProgram::DumpText {
                mode: dump_text_mode,
                idle_ms: dump_text_idle_ms,
                max_wait_ms: dump_text_max_wait_ms,
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
        }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dump_text_mode_aliases() {
        assert_eq!(parse_dump_text_mode("innertext"), Some(DumpTextMode::InnerText));
        assert_eq!(parse_dump_text_mode("INNER-TEXT"), Some(DumpTextMode::InnerText));
        assert_eq!(parse_dump_text_mode("accessibility"), Some(DumpTextMode::Accessibility));
        assert_eq!(parse_dump_text_mode("a11y"), Some(DumpTextMode::Accessibility));
        assert_eq!(parse_dump_text_mode("raw-dom"), Some(DumpTextMode::RawDom));
        assert_eq!(parse_dump_text_mode("OuterHTML"), Some(DumpTextMode::RawDom));
        assert_eq!(parse_dump_text_mode("nope"), None);
    }

    #[test]
    fn viewport_parsing() {
        assert_eq!(parse_viewport("1280x800"), Some((1280, 800)));
        assert_eq!(parse_viewport("1280X800"), Some((1280, 800)));
        assert_eq!(parse_viewport("0x800"), None);
        assert_eq!(parse_viewport("abcxdef"), None);
    }
}
