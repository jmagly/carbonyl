use super::CommandLine;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DumpTextMode {
    /// `document.body.innerText` style — visual order, formatted.
    InnerText,
    /// Accessibility tree dump — semantic structure. Backed by issue #4.
    Accessibility,
    /// `document.documentElement.outerHTML` — no transformation.
    RawDom,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DumpFrameFormat {
    /// PNG image encoded from the latest compositor frame.
    Png,
}

#[derive(Clone, Debug)]
pub enum CommandLineProgram {
    Main,
    Help,
    Version,
    /// `--dump-text[=mode]` — load the URL, wait for the page, emit text on
    /// stdout, exit. Bypasses the terminal renderer entirely. See #88.
    DumpText {
        mode: DumpTextMode,
        idle_ms: u64,
        max_wait_ms: u64,
    },
    /// `--dump[=png]` / `--screenshot[=png]` — load the URL, wait for
    /// compositor frames to settle, emit the current frame as PNG on stdout,
    /// and exit. Bypasses the terminal renderer entirely. See #206.
    DumpFrame {
        format: DumpFrameFormat,
        idle_ms: u64,
        max_wait_ms: u64,
    },
}

impl CommandLineProgram {
    pub fn parse_or_run() -> Option<CommandLine> {
        let cmd = CommandLine::parse();

        match cmd.program {
            CommandLineProgram::Main => {
                // #125 cycle 2: the framebuffer output sink is live — frames are
                // blitted to the device at full resolution *additively*, while
                // the terminal renderer keeps running (modeled on the X-mirror).
                // Input is additive too: the stdin/terminal path stays active and
                // a bare console is served by the evdev reader (/dev/input/event*),
                // which needs the `input`/`video` group or root. The device is
                // opened in the bridge (carbonyl_renderer_create), which logs the
                // typed FbError and falls back to terminal-only on failure.
                // See docs/framebuffer-backend.md.
                if let Some(path) = &cmd.framebuffer {
                    eprintln!(
                        "carbonyl: framebuffer output enabled ({path}) — rendering \
                         full-resolution frames alongside the terminal renderer; \
                         local-console input via evdev (needs the input/video group \
                         or root). See docs/framebuffer-backend.md."
                    );
                }
                return Some(cmd);
            }
            CommandLineProgram::Help => {
                println!("{}", include_str!("usage.txt"))
            }
            CommandLineProgram::Version => {
                println!("Carbonyl {}", env!("CARGO_PKG_VERSION"))
            }
            CommandLineProgram::DumpText { .. } => {
                // Returning to the caller (the Main path in bridge.rs) so
                // chromium proceeds in-process. The C++-side handler
                // (`carbonyl::DumpTextHandler`, installed via patch 0027) is
                // gated on the `--carbonyl-dump-text` chromium switch, which
                // `bridge.rs::main()` appends to argv before chromium init.
                // Implementation lives in:
                //   chromium/src/carbonyl/src/browser/dump_text_handler.cc
                return Some(cmd);
            }
            CommandLineProgram::DumpFrame { .. } => {
                // Returning to the caller lets chromium proceed in-process with
                // stdout still connected to the user's pipe. The Rust bridge
                // owns frame-idle detection and PNG emission.
                return Some(cmd);
            }
        }

        None
    }
}
