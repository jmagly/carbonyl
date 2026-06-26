# License Review

Issue: #24

## Recommendation

Keep Carbonyl under `BSD-3-Clause`.

This fork inherits upstream Carbonyl's permissive BSD-3-Clause license and is
built as a patched Chromium headless runtime. Staying with BSD-3-Clause keeps
the fork aligned with both upstream Carbonyl and Chromium, avoids a relicensing
decision for inherited code, and remains compatible with the Rust dependency
set currently accepted by `deny.toml`.

Do not migrate the whole project to Apache-2.0, MIT, GPL-3.0, or another
license without a contributor-rights review. Apache-2.0 and MIT are generally
compatible for new permissive code, but changing the project-level license would
require clearly separating inherited BSD-3-Clause code from any newly licensed
code. GPL-3.0 would materially change downstream obligations and is not a good
fit for this Chromium-derived runtime.

## Current Evidence

- Upstream `fathyb/carbonyl` is detected by GitHub as
  `BSD-3-Clause`, with license file `license.md`:
  <https://api.github.com/repos/fathyb/carbonyl/license>
- This repository's root `LICENSE` is the BSD-3-Clause text carrying the
  original 2023 Fathy Boundjadj copyright notice.
- `package.json`, `package-lock.json`, `scripts/npm-package.mjs`, and the
  Linux packaging metadata already declare `BSD-3-Clause`.
- `Cargo.toml` now declares `license = "BSD-3-Clause"` so `cargo metadata`
  and cargo-deny see the crate license directly.
- Chromium's checkout has its own BSD-style license at `chromium/src/LICENSE`.
  Redistributors must preserve Chromium notices and third-party notices from the
  Chromium tree.
- `deny.toml` currently allows only permissive Rust dependency licenses present
  in the crate graph: `MIT`, `Apache-2.0`, `BSD-3-Clause`, and
  `Unicode-DFS-2016`.

## Constraints

- Chromium and Blink code remain under their upstream license terms. Carbonyl's
  patches and injected sources can be BSD-3-Clause, but the Chromium license
  notices must remain intact in source and binary distributions.
- Vendored Chromium third-party code includes many separate notices. A release
  artifact must preserve Chromium's license/notice bundle rather than relying
  only on the root Carbonyl `LICENSE`.
- Headers in Carbonyl-owned C++ files should point to the root BSD-style
  `LICENSE`. The `src/blink/*` Carbonyl-owned files previously said
  "MIT-style" while pointing to the BSD root license; those headers are now
  corrected to BSD-style.
- Rust dependencies should continue to be checked with cargo-deny before adding
  new crates or relaxing `deny.toml`.

## Migration Path

1. Keep the root `LICENSE` as BSD-3-Clause.
2. Keep package metadata (`Cargo.toml`, `package.json`, native packaging)
   synchronized on `BSD-3-Clause`.
3. For new Carbonyl-owned source files, use either an SPDX header:
   `SPDX-License-Identifier: BSD-3-Clause`, or the existing Chromium-style
   two-line BSD header when the file lives in Chromium-adjacent C++/GN code.
4. For copied or adapted third-party source, preserve the original header and
   add a local note in the nearest documentation or `README.chromium`-style
   file if needed.
5. Before a future license change, run a contributor-rights audit over inherited
   upstream Carbonyl code, Carbonyl fork contributions, and vendored Chromium
   modifications. Treat that as a legal/release-management decision, not a
   routine docs cleanup.
