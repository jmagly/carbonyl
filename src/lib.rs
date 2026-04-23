// Crate-wide lint suppressions.
// - identity_op: `<< 0`, `x + 0` are used intentionally for bit-position /
//   visual alignment with neighbouring rows. Rewriting them destroys the
//   parallel structure readers rely on.
// - crate_in_macro_def: declarative macros reference `$crate::...` forms
//   that clippy misidentifies as unqualified `crate` uses.
// - upper_case_acronyms: public types like `TTY` are intentional; renaming
//   them would break downstream callers.
// - module_inception: `cli::cli` is a deliberate submodule layout.
#![allow(
    clippy::identity_op,
    clippy::crate_in_macro_def,
    clippy::upper_case_acronyms,
    clippy::module_inception
)]

pub mod browser;
pub mod cli;
pub mod gfx;
pub mod input;
pub mod output;
pub mod ui;

mod utils;
