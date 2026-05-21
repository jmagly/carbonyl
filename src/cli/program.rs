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
}

impl CommandLineProgram {
    pub fn parse_or_run() -> Option<CommandLine> {
        let cmd = CommandLine::parse();

        match cmd.program {
            CommandLineProgram::Main => return Some(cmd),
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
        }

        None
    }
}
