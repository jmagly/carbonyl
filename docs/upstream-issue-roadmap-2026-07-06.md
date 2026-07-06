# Upstream Issue Audit and Roadmap - 2026-07-06

Scope: open issues in `fathyb/carbonyl` after the fork's June fixes and the
Chromium M150 bump branch. Local tracker references are `roctinam/carbonyl`
Gitea issue numbers unless noted.

## Current State

- Upstream `fathyb/carbonyl`: 80 open issues and 9 open pull requests.
- GitHub mirror `jmagly/carbonyl`: no active upstream-mirror issue backlog; it
  only has two closed local issues. The actionable mirror is the private Gitea
  tracker.
- Private tracker: upstream mirrors are labeled `upstream-map`; most were
  initially parked as `agentic: later`. This audit promotes near-term work,
  leaves speculative backlog parked, and closes items outside the fork roadmap.
- Chromium baseline: `scripts/patches.sh` pins Chromium 150.0.7871.47 on the
  active `chore/chromium-m150-bump` branch.

## Resolved By Current Fork Work

These upstream issues are either fixed in the fork or have a local verification
path. Upstream remains open because we do not control `fathyb/carbonyl`.

| Upstream | Local | Disposition | Evidence |
|---|---:|---|---|
| #223, #212, #131 non-ASCII / Chinese / Cyrillic input | #178/#217 history | Fixed | `src/input/utf8.rs`, widened key FFI in patch `0009`, `test/repro/issue-178/` |
| #97 Tab inserts text instead of advancing focus | #169 history | Fixed | `test/repro/issue-169/`, patch `0009` sets `VKEY_TAB` and `DomKey::TAB` |
| #163 right-click | #199 history | Fixed | mouse-button FFI, `test/repro/issue-199/` |
| #136 invert colors | #181 history | Fixed | `src/ui/navigation.rs`, `src/output/painter.rs`, documented shortcut in `src/cli/usage.txt` |
| #148 pass flags to Chromium | #188 history | Fixed | CLI preserves unknown Chromium switches; docs/tests added in commit `0d15887` |
| #137 downloads | #182 history | Fixed | `--download-dir`, `CARBONYL_DOWNLOAD_DIR`, `test/repro/issue-182/` |
| #177 file/folder picker prompt | #208 history | Fixed | `--file-dialog-path`, Chromium patch `0034` |
| #174 dump current frame | #206 history | Fixed | `--dump-frame`, PNG/sixel/kitty/iTerm2 paths, `test/repro/issue-241/measure.sh` |
| #132 dump rendered HTML/text | #88 history | Partial/fixed for text | `--dump-text`, raw DOM/accessibility modes; HTML snapshot is not the primary roadmap |
| #118 sandbox error docs | #173 history | Fixed/docs | install/runtime docs cover `--no-sandbox` constrained environments |
| #138 npm release gap | #280 | Superseded | fork publishes release assets and GHCR image instead of old upstream npm release flow |
| #172 `.deb` package | #129 history | Fixed | Linux `.deb`/`.rpm`/AppImage packaging and docs |
| #214 macOS Gatekeeper | #245/#266 | Documented; signing tracked separately | `docs/install.md`, `packaging/macos/GATEKEEPER.txt`, open #266 for Developer ID notarization |
| #181 Docker blank after one second | #210 history | Characterized/fixed infra | GPU-less harness explains idle-frame behavior; top-level Docker runtime libs fixed |
| #197 cross-platform README expectations | #276 | Fixed/docs | Current install/platform docs and Windows out-of-scope decisions cover this |
| #210 community fork discussion | #279 | Routed | Roadmap split concrete asks into #241, #190/#209, #278, #265, and platform drops |

## Do Next

These are worth doing or re-testing against M150. They should be labeled
`agentic: needed` and generally `priority: should`.

| Local | Upstream | Why keep | Next action |
|---:|---|---|---|
| #241 | #11 | Terminal image protocols are the main path to higher-fidelity rendering. | Finish sixel/kitty/iTerm2 runtime polish; keep default renderer unchanged. |
| #265 | #198 | PDF visual/interactivity remains a real browser gap; text extraction is done but not enough. | Retest Overleaf/PDF viewer on M150; decide between native PDF plugin, fallback download, or viewer limitation docs. |
| #160 | #19 | Amazon/regional text rendering is a high-signal rendering regression class. | Run `test/repro/issue-160/` on the M150 runtime and classify DOM-vs-terminal failure. |
| #216 | #211 | Key modifiers landed after the original report; macOS shortcut behavior needs re-test. | Verify Cmd/Ctrl/Alt shortcut mapping on macOS runtime. |
| #177 | #124 | SSH input reports may be resolved by the input FFI fixes but need explicit terminal/tmux coverage. | Re-test over SSH/tmux with SGR mouse enabled. |
| #184 | #140 | PuTTY mouse is likely a small terminal-mode compatibility fix. | Evaluate DECSET 1002 in addition to 1003/1006. |
| #172 | #116 | Resize artifacts are core terminal UX. | Add a deterministic resize repaint harness. |
| #187 | #147 | JavaScript alert/basic dialog handling is a small but visible browser gap. | Implement or document alert/confirm/prompt behavior in headless mode. |
| #191 | #152 | Implicit `https://` is low risk and improves everyday navigation. | Add URL normalization for bare hosts in local chrome. |
| #176 | #123 | `prefers-color-scheme` improves page readability and can be mapped from terminal background. | Add CLI/env override first, auto-detect later. |
| #202 | #167 | Copy/select is a recurring terminal-browser usability gap. | Define whether this is terminal selection, DOM selection, or clipboard integration. |
| #278 | #202 | Concrete report of hyperlink click failures over SSH. | Retest with M150 over SSH/Termux/Konsole; route with #177 and #184 terminal mouse work. |
| #190/#209 | #151/#178 | Keybindings/vim navigation are useful but must not break page input. | Design behind an opt-in mode after shortcut re-test. |

## Drop / Close Locally

These do not match the fork's near-term roadmap or are superseded by a better
local tracker.

| Local | Upstream | Close reason |
|---:|---|---|
| #163 | #46 | Native Windows build is out of scope; WSL/Docker/release assets remain the supported path. |
| #215 | #204 | Portable Windows packaging is out of scope while native Windows is out of scope. |
| #220 | #217 | WSL `/bin/bash` launch failure is a host install/WSL environment issue, not a Chromium/runtime bug. |
| #198 | #161 | WASM build is incompatible with Chromium runtime + native terminal integration goals. |
| #193 | #155 | Chromebook-specific support is not a maintained target. |
| #170 | #107 | CentOS 7 support is outside the supported distribution set. |
| #218 | #213 | WebAudio polyfill work is not a Carbonyl runtime priority; Chromium owns WebAudio, terminal audio UX is separate. |
| #186 | #145 | Superseded by #241 terminal image-protocol work. |
| #201 | #165 | High-res URL bar pressure should be handled by #241 and chrome-row/layout work, not a separate issue. |
| #280 | #138 | Old upstream npm release gap; superseded by release assets, signed packages, and container image flow. |
| #271 | #146 | Old upstream npm/Homebrew wrapper failure; fork uses release assets and native packages instead. |
| #273 | #162 | Status/community discussion answered by maintained fork status and #270. |
| #274 | #175 | Donation/sponsorship request belongs to governance/site work, not runtime backlog. |
| #275 | #196 | Duplicate project-alive status question answered by maintained fork status and #270. |
| #277 | #201 | Non-technical status/speculation issue; not actionable runtime work. |
| #279 | #210 | Community-fork umbrella split into concrete roadmap items; no separate umbrella work remains. |

## Backfilled Mirrors

The first audit pass found nine upstream-open issues that had no local
`upstream-map` mirror. They are now represented locally:

| Local | Upstream | State | Disposition |
|---:|---|---|---|
| #271 | #146 | Closed | Old npm/Homebrew wrapper failure; not planned. |
| #280 | #138 | Closed | Old npm release gap; superseded by current release asset/package/container flow. |
| #272 | #153 | Open | Parked docs/community material for real-world usage examples. |
| #273 | #162 | Closed | Project-status question answered by #270. |
| #274 | #175 | Closed | Donation options out of runtime scope. |
| #275 | #196 | Closed | Duplicate project-status question answered by #270. |
| #276 | #197 | Closed | Cross-platform docs covered by current install/platform docs and Windows drops. |
| #277 | #201 | Closed | Non-technical status/speculation issue. |
| #278 | #202 | Open | Actionable SSH hyperlink-click report; route with #177/#184. |
| #279 | #210 | Closed | Community-fork umbrella split into concrete roadmap items. |

## Parked Backlog

Keep these as `agentic: later` unless a user or downstream product needs them.

- Platform/distribution: #116, #165, #194, #196.
- Browser features: #152, #155, #156, #158, #159, #180, #185, #192, #195.
- Docs/community: #272.
- Automation/fingerprint epic: #58 remains open; CAPTCHA/anti-bot upstream
  issues (#164/#170/#200 and related) should route through that epic or sibling
  `carbonyl-agent` work, not standalone Carbonyl one-offs.
- Maintenance docs/catalogs: #39, #41, #42, #44, #45, #229.

## Roadmap

### Phase 0 - M150 Verification

- Merge/complete #269 and close #114 when the runtime bump is proven.
- Re-run focused repros: `issue-160`, `issue-168-211`, `issue-169`,
  `issue-178`, `issue-199`, `issue-213`, `issue-237`, `issue-241`.
- Update upstream-map issue comments with M150 pass/fail evidence before
  closing any browser-behavior bugs as resolved.

### Phase 1 - Rendering Fidelity

- Finish #241 terminal image protocols as opt-in output paths.
- Retest #160 Amazon/regional text and #265 PDF visual rendering.
- Decide whether #185 icon fonts and #155 text effects become renderer work or
  stay parked until the image-protocol path stabilizes.

### Phase 2 - Interaction UX

- Retest #216/#177/#184/#278 on real terminal environments.
- Add resize repaint coverage for #172.
- Implement small local-chrome improvements: #191 implicit HTTPS and #176 color
  scheme override.

### Phase 3 - Product Backlog

- Decide on #202 copy/select and #190/#209 keybinding mode after Phase 2 input
  compatibility is stable.
- Keep Windows/WASM/Chromebook/CentOS/audio-polyfill requests closed unless the
  project explicitly adopts those platforms.
