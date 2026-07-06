---
title: "Carbonyl suite — June 2026 Report"
slug: "2026-6-carbonyl-june-2026-report"
date: "2026-06-30"
project: "carbonyl"
type: report
tags: [report, "2026-06", "carbonyl", "browser-automation"]
summary: "A big month for the terminal browser itself: a steady run of releases cleared long-standing input bugs — right-click, other-language typing, key combos, and Tab focus — while downloads became signed and verifiable, native installers and a container image landed, and the headless 'read the page as text' mode grew."
reading_time: 10
status: "published"
pillar: "1 report"
audience: "Carbonyl users and evaluators who want the June 2026 release summary"
hero: "/assets/blog/2026-6-carbonyl-june-2026-report.png"
---

# Carbonyl suite — June 2026

![A real web page rendered as glowing colored structure inside a terminal window, with an accessibility-tree/extraction motif of nodes flowing out to one side.](/assets/blog/2026-6-carbonyl-june-2026-report.png)

Hero image: AI-generated with ChatGPT from a brand-specified prompt; no text or logos are AI-rendered.

*Carbonyl is a real web browser that runs inside your terminal. It shows web pages as colored blocks of text, right in the terminal window — no desktop, no graphics screen needed. It was first built by Fathy Boundjadj; this is the actively maintained version. Around the browser, the suite adds a toolkit agents use to drive it, a manager for many sessions at once, a library of "looks like a real browser" profiles, and an automated tester. It is the browser-automation layer of the Agentic Operating System.*

## TL;DR

June was a busy month for the browser itself. The team shipped a steady run of releases and worked through a backlog of long-standing bugs — including ones open since the original project. The biggest theme was **input**: the browser can now take the kinds of typing and clicking it used to drop. Right-click works. You can type in other languages, like Russian, Chinese, Japanese, and Korean. Key combinations like Shift+Tab and Ctrl/Alt/Meta now reach the page. Tab can move between fields. On top of that, every download is now **signed and checkable**, native installers and a ready-to-run container image landed, and the "read a page as plain text" mode grew. The toolkit that agents use to drive the browser was quiet this month; the browser underneath did the moving.

## By the numbers

| What's public | Value |
|---|---|
| What it is | A real web browser that runs in your terminal — no screen needed |
| Originally by | Fathy Boundjadj; this is the actively maintained version |
| The suite around it | The browser · an agent toolkit · a session manager · a fingerprint library · an automated tester |
| Released this month | A run of v0.2.0-alpha releases (see Releases) |
| How to get it | Native installers (.deb / .rpm / .AppImage / .pkg / .dmg) and a container image |
| Downloads | Now signed; verify with a published key (see magly.net) |
| Source · container | github.com/jmagly/carbonyl · ghcr.io/jmagly/carbonyl |

## Highlights

**1. Right-click works.**
What it is: the browser now knows which mouse button you pressed, so right-click reaches the page.
How you'd use it: open a context menu, or use a site that needs a right-click — it just works now.
Why it helps: a whole class of pages that depend on the right button stopped being dead ends.

**2. Type in any language.**
What it is: the browser now accepts multi-byte characters — letters and symbols beyond plain English, like Cyrillic and Chinese, Japanese, and Korean.
How you'd use it: type a search or fill a form in your own language and the page receives it correctly.
Why it helps: before, those keystrokes were dropped. Now the browser works for the rest of the world's writing, not just ASCII.

**3. Key combinations carry through.**
What it is: modifier keys now reach the page — Shift+Tab to move backward through a form, and Ctrl, Alt, or Meta held with another key.
How you'd use it: press Shift+Tab to step back a field, or use a site's keyboard shortcuts as you would in a normal browser.
Why it helps: keyboard-driven sites and forms become usable instead of half-working.

**4. Tab moves between fields — when you want it to.**
What it is: pressing Tab can now move focus from one field to the next, the way it does in a desktop browser. It is off by default and you turn it on with a flag.
How you'd use it: switch it on when you're filling a form; leave it off when you want your terminal to handle Tab itself.
Why it helps: you get proper form navigation without the browser stealing the Tab key from your terminal.

**5. Read a page as plain text — now richer.**
What it is: a mode that skips the visual display and just prints a page's content, built for scraping and feeding text to AI. This month it gained three things. A clean "accessibility tree" view — the page's real structure of headings, links, and labels. The ability to pull text out of embedded PDFs. And a mode that saves what the browser shows as a PNG image.
How you'd use it: point the browser at a page and capture its text — or a snapshot image — straight from the command line, no screen involved.
Why it helps: it turns the browser into a clean source of page content for agents and pipelines.

**6. Downloads you can trust.**
What it is: every release file now comes with a checksum and a GPG signature. That's a stamp you can check. It proves the file really came from the project and wasn't tampered with. The signing key is published. The project's checks for leaked secrets and risky dependencies now run on every change, and must pass.
How you'd use it: before installing, verify the download against the published key (see magly.net).
Why it helps: you can be sure the browser you install is the real, untampered one — important for something that runs web pages.

## Features shipped

**Input that finally works (the headline).** The month's biggest push fixed how the browser receives keyboard and mouse input — much of it long-standing limitations from the original project. The mouse now carries which button you pressed, so **right-click** works. Typing now accepts **multi-byte characters**. Cyrillic and CJK (Chinese, Japanese, Korean) text reaches the page instead of being dropped. **Key modifiers** now carry across to the page, so Shift+Tab (move backward) and Ctrl/Alt/Meta combinations work. **Tab focus traversal** moves between fields. It was added, then made opt-in with a flag, so it doesn't grab the Tab key your terminal needs. There's also a keyboard shortcut to **invert page colors** for easier reading.

**Headless extraction grew.** The "read the page as text, no screen" mode matured. It now produces a real **accessibility tree** — the page's structured outline of headings, links, and labels. That is cleaner for machines than raw text. It can pull **text out of embedded PDFs**. And a new **PNG frame dump** saves what the browser shows as an image file. Together these make the browser a solid way to turn any page into clean content for agents and pipelines.

**Easy to install, everywhere.** The browser now ships as proper native installers. There are **.deb**, **.rpm**, and a portable **.AppImage** for Linux, plus a **.pkg / .dmg** for macOS on Apple Silicon. There's also a ready-to-run **container image** (`ghcr.io/jmagly/carbonyl`). You can run the browser with a single command and nothing to set up. The Linux packages declare what they need, so your package manager pulls it in.

**Render with no graphics system (groundwork).** The first cycle of a new output path lets the browser draw straight to a Linux framebuffer — the raw screen. So it can show full-resolution pages on a plain console, with no X11 or Wayland. This suits kiosks, appliances, and recovery consoles. It is built in but dormant for now; the terminal display remains the default.

## Fixes

Most of the month's fixes were the input work above — turning dropped keystrokes and clicks into ones that reach the page. The team also kept the browser's patch set — the changes layered on top of Chromium — building cleanly as those input changes landed. That included a fix so it still builds on macOS. The release pipeline was tightened too. Build-only "runtime" cuts are now marked as previews, so they don't get promoted ahead of real releases. And the step that copies release files to GitHub no longer fails when a release is re-run.

A smaller tooling regression in the suite's QA runner was wrapped up at the start of the month. On the newest Docker and Linux kernel, virtual keyboard and mouse devices didn't appear inside a container. The fix was to document the supported way to run that kind of test — inside a small virtual machine — rather than weaken the container's isolation.

## Performance & reliability

The reliability story this month is mostly safety at the edges. The bridge between the browser's Rust and C++ halves was hardened. Bad or malformed input can no longer crash the process. It now checks its inputs and fails safely instead. The release process was also made repeatable, so re-running a release no longer errors partway through. No general speed work shipped this month.

## Breaking changes & migrations

None that affect normal use. Everything is additive. One thing to know: the new "read a page as text" accessibility mode now outputs the page's structured tree instead of plain text, so anything that reads that specific mode should expect the new shape. Tab-to-move-focus is off by default, so nothing changes unless you turn it on.

## Releases

The browser shipped a steady run of preview releases through the month, each public on the project's releases page. Highlights by version:

- **v0.2.0-alpha.8** (Jun 4) — the "read as text" mode gained a real accessibility-tree view.
- **v0.2.0-alpha.9** (Jun 14) — native installers: .deb, .rpm, .AppImage (Linux) and .pkg/.dmg (macOS Apple Silicon).
- **v0.2.0-alpha.10** (Jun 15) — a published container image (`ghcr.io/jmagly/carbonyl`); first cycle of the framebuffer (raw-screen) output path; sturdier packaging.
- **v0.2.0-alpha.11** (Jun 17) — runtime refresh.
- **v0.2.0-alpha.12** (Jun 20) — invert-colors shortcut; full-page capture.
- **v0.2.0-alpha.13** (Jun 22) — the big input release: right-click, multi-byte (Cyrillic/CJK) typing, key modifiers (Shift+Tab, Ctrl/Alt/Meta), and Tab focus.
- **v0.2.0-alpha.14** (Jun 22) — a macOS build fix for the Tab change.
- **v0.2.0-alpha.15** (Jun 23) — signed releases: GPG signatures and checksums on every file, a published signing key, and supply-chain plus secret scanning in the build.
- **v0.2.0-alpha.16** (Jun 25) — save a page snapshot as a PNG image.

These are preview ("alpha") releases — the browser is maturing toward a stable line. Pre-built runtime files are attached to each release for download.

## Dependencies & security

Security was a real second theme. Every release file now ships with a checksum and a per-file **GPG signature**. It's signed with a dedicated, published release key, which you can verify via magly.net. So you can confirm a download is genuine and untampered. The project also added automated **supply-chain and secret scanning** — checks for leaked credentials, risky dependencies, and license problems. These were then promoted to required checks that must pass on every change. A known dependency advisory was cleared by updating the affected library. And the **Rust↔C++ boundary was hardened** so bad input from the native side can't crash or corrupt the browser.

## Docs & developer experience

The install and verification docs grew with the new packages: how to install on each platform, how to clear the macOS "unidentified developer" prompt, and how to verify a download against the signing key. A short research note looked into showing real images in terminals that support it (the "sixel" picture protocol). It builds on an old request from the original project. It's kept as research for now; the current text-block renderer stays the default. Across the suite's project pages, a "Built With AIWG" badge was added.

## Tests & CI

New test harnesses backed the month's features — checks that Tab focus advances, that full-page capture works, and a way to reproduce rendering on machines with no graphics card. The build pipeline gained the supply-chain and secret scans described above, now required. It also made its release-file copying repeatable. And it kept the Chromium patch set verified before each merge.

## Cross-project impact

- The browser is the engine the rest of the suite drives: the **agent toolkit** (carbonyl-agent), the **session manager** (carbonyl-fleet), the **fingerprint library**, and the **QA runner** all sit on top of it. This month's input fixes flow straight into what agents can do — logging in, filling forms, and using keyboard-driven sites.
- For tests that need "real" keyboard and mouse input where Docker can't safely provide it, the sibling **agentic-sandbox** project offers a small-virtual-machine path. The two projects cover each other.
- Carbonyl is the **browser-automation layer of the Agentic Operating System** — how agents in the wider stack use the web like a person, on servers with no screen.

## Known issues & open threads

- **Apple Silicon Linux (arm64) builds** aren't shipped yet — they wait on dedicated build hardware. macOS Apple Silicon and Linux x86 are covered.
- The **framebuffer (raw-screen) output** is built in but dormant — a later cycle wires it into the live display.
- The **macOS app bundle isn't Apple-notarized** yet, so macOS shows a first-launch prompt; the bypass and the GPG verification are documented. Notarization is planned.
- **Real terminal images (sixel)** remain a research item, not a shipped feature.
- More **upstream backlog** from the original project continues to be worked through.

## What's next

Keep clearing the upstream bug backlog, wire the framebuffer output into the live display, extend builds to Apple Silicon Linux, and continue the path toward a stable (non-preview) release. Steady preview releases will keep coming.

## Appendix

- **What it is:** a real web browser that runs in your terminal — originally by Fathy Boundjadj, now actively maintained. Part of the Carbonyl suite (browser · agent toolkit · session manager · fingerprint library · QA runner).
- **Released this month:** the v0.2.0-alpha.8 through alpha.16 preview series, published to the project's releases page.
- **How to get it:** native installers (.deb / .rpm / .AppImage / .pkg / .dmg) and a container image (`ghcr.io/jmagly/carbonyl`).
- **Verify downloads:** checksums + GPG signature; the signing key is published (see magly.net).
- **Source:** github.com/jmagly/carbonyl (browser) · -agent · -fleet · -fingerprint-corpus · -agent-qa (suite) · window: all of June 2026.
- **Related:** agentic-sandbox (provides the virtual-machine path for trusted-input QA).
