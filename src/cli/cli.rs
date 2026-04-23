use std::{env, ffi::OsStr};

use super::CommandLineProgram;

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
        let mut program = CommandLineProgram::Main;
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
