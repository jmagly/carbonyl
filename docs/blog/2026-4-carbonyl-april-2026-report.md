---
title: "Carbonyl suite — April 2026 Report"
slug: "2026-4-carbonyl-april-2026-report"
date: "2026-04-30"
project: "carbonyl"
type: report
tags: [report, "2026-04", "carbonyl", "browser-automation"]
summary: "April was the inception month for the maintained Carbonyl suite: the fork moved to modern Chromium, the first public alpha shipped, and the surrounding automation SDK, fleet server, fingerprint corpus, and QA harness took shape."
reading_time: 9
status: "published"
pillar: "1 report"
audience: "Carbonyl users and evaluators who want the April 2026 inception summary"
---

# Carbonyl suite — April 2026

*Carbonyl is a real web browser that runs inside your terminal. It was first built by Fathy Boundjadj. This report starts at our fork point and covers our maintained suite work only. It does not retell the full upstream history.*

## TL;DR

April was the starting month for the maintained Carbonyl suite. The browser fork was brought from its older upstream base onto a current Chromium line, then released as the first public alpha of the maintained fork. The team also split the Python automation layer into its own SDK, started the fleet server for many browser sessions, and laid the first pieces of a trusted-input and fingerprint story. By the end of the month, Carbonyl was no longer just a terminal browser fork. It was becoming a browser automation stack.

## By the numbers

| What's public | Value |
|---|---|
| What it is | A Chromium-based browser that renders into a terminal |
| Origin | Maintained fork of the original Fathy Boundjadj Carbonyl project |
| Public browser releases | `v0.2.0-alpha.1` and `v0.2.0-alpha.3` |
| Companion projects started | `carbonyl-agent`, `carbonyl-fleet`, `carbonyl-fingerprint-corpus`, `carbonyl-agent-qa` |
| Browser baseline | Chromium M147 for the first maintained alpha line |
| Runtime distribution | Release assets instead of the older upstream CDN |
| Public source | github.com/jmagly/carbonyl |

## Highlights

**1. The maintained fork became real.**
What it is: Carbonyl was rebased from the old upstream era onto a modern Chromium base. The first maintained alpha was published from the fork.
How you'd use it: install the runtime from the maintained release assets instead of relying on old upstream packages.
Why it helps: you get a terminal browser that can keep moving with Chromium instead of staying tied to a dated browser core.

**2. Runtime downloads moved to release assets.**
What it is: the browser runtime is packaged as a release asset, with an installer path through `carbonyl-agent`.
How you'd use it: run `pip install carbonyl-agent`, then let the SDK install the matching runtime.
Why it helps: setup is easier to automate. It also gives operators a clear place to pin and fetch known runtime builds.

**3. The Python automation SDK split out.**
What it is: browser-driving code moved into `carbonyl-agent`, a Python package that starts Carbonyl, reads terminal output, and manages sessions.
How you'd use it: write a Python script that opens a page, waits, reads `page_text()`, clicks, types, and closes cleanly.
Why it helps: users who want automation do not need to work inside the browser source tree.

**4. Multi-browser orchestration started.**
What it is: `carbonyl-fleet` began as a server for running many Carbonyl browsers with HTTP, gRPC, sessions, snapshots, and authentication.
How you'd use it: point a service at the fleet server when you need more than one browser at a time.
Why it helps: browser automation becomes a service you can supervise, secure, and scale.

**5. Visual capture became part of the plan.**
What it is: Carbonyl gained an X-mirror mode that can copy compositor frames into an X window while the terminal renderer still runs.
How you'd use it: run the X11 variant when you need screenshots or video capture from the same browser session.
Why it helps: agents can keep using the terminal view, while test and audit tools can capture real pixels.

**6. The trusted-input track got its first shape.**
What it is: the suite began separating plain terminal automation from higher-trust input paths that can go through real OS input devices.
How you'd use it: keep using the default PTY path for simple browsing, and reserve the heavier setup for sites that need trusted keyboard or mouse events.
Why it helps: the stack can grow toward harder login and form flows without making every user run a complex desktop environment.

## Features shipped

**Modern browser base.** The maintained fork moved to a modern Chromium line and shipped the first public alpha. That matters because web compatibility is tied to Chromium. A terminal browser that falls too far behind starts failing on normal pages. The April work made future rebases and patch maintenance part of the project, not a one-time rescue.

**Text capture survived the rebase.** Carbonyl's text-capture path was reworked so it could live cleanly with newer Chromium internals. For users, the simple outcome is that the browser could still expose page text after the browser engine moved forward. That is a key feature for agents, because text is cheaper and easier to feed to a model than screenshots.

**Automation moved into `carbonyl-agent`.** The Python layer became its own package. It provides `CarbonylBrowser`, session persistence, daemon support, screen inspection, click helpers, and install support for the runtime. If you are building an agent, this is the package you use day to day. The browser repo can focus on the runtime, while the SDK can focus on developer ergonomics.

**The fleet server began.** `carbonyl-fleet` started as a Rust service for many browser sessions. It brought a typed service layout, a Python SDK, session storage, browser supervision, bearer-token authentication, snapshot integrity, and loopback-safe defaults. The value is simple: one browser is a tool; many supervised browsers become infrastructure.

**Trusted-input groundwork started.** The suite began exploring when terminal writes are enough and when real OS input is needed. `carbonyl-agent` gained uinput-related work, and `carbonyl-agent-qa` began carrying tests and spikes for input behavior. This was not yet a polished public feature, but it set the direction for later login and form automation.

**A fingerprint corpus was started.** `carbonyl-fingerprint-corpus` was created as data support for realistic browser personas. In plain terms, this is the reference material that helps keep browser claims, network behavior, and JavaScript-visible details consistent. The public SDK work later consumes this direction through typed personas and checks.

**X-mirror added a second output surface.** The browser gained an optional mode that mirrors frames to X11. This is useful for audit captures, video, and tests that need pixel evidence. It stays off by default, so normal terminal use keeps its small surface.

## Fixes

April was mostly inception and rebase work, but it also fixed several user-visible risks.

The browser build was repaired across multiple Chromium jumps. The text-capture path was kept working after the rebase. The viewport work made layout more predictable when callers provide a CSS viewport. CI and release scripts were hardened so runtime builds could be repeated with fewer manual steps.

For the SDK, early fixes improved click targeting, coordinate consistency, daemon reconnect behavior, user-agent choices, and shutdown behavior. These are the small things that decide whether a browser script feels dependable or brittle.

## Performance & reliability

The main reliability win was getting onto a maintained Chromium base and making that build repeatable. Carbonyl also added smoke tests for text capture and visual output. `carbonyl-fleet` added process supervision ideas such as graceful shutdown, orphan cleanup, and resource controls. `carbonyl-agent` added session and daemon features that let browser state survive beyond one short script.

## Breaking changes & migrations

The maintained fork changed where users should get the runtime. Runtime files now come from maintained release assets, not the old upstream CDN.

The Python automation layer also moved out of the browser repo. Existing users should treat `carbonyl-agent` as the public SDK and install it separately.

## Releases

**`v0.2.0-alpha.1` — April 2026.**
This was the first public alpha of the maintained fork. It moved the runtime to Chromium M147, kept text capture alive, published a Linux x86 runtime asset, and established `carbonyl-agent` as the recommended install path.

**`v0.2.0-alpha.3` — April 2026.**
This release added the X-mirror output surface, separate runtime lanes for terminal-only and X11 builds, dual-output validation, and stronger release workflows. It also rolled in the explicit `--viewport=WIDTHxHEIGHT` layout control.

## Dependencies & security

Security work in April was mostly about safe foundations. The fork moved to a maintained Chromium base. `carbonyl-fleet` defaulted to loopback binding and bearer-token authentication. Snapshot integrity, filesystem permissions, and process-hardening work started in the fleet server. The SDK added runtime checksum verification and clearer install paths.

## Docs & developer experience

April added the first full public-facing docs for the maintained fork and its sibling projects. The browser README was reshaped around the maintained fork, the SDK, and the fleet server. Operator docs explained runtime modes, CI runners, and build steps. The SDK README explained sessions, daemon mode, install behavior, and the basic browser API.

## Tests & CI

CI became part of the project rather than an afterthought. The browser added Rust checks, Chromium build workflows, release workflows, mirror workflows, and smoke tests for text capture and visual output. The SDK added package and runner workflows. The QA repo began carrying tests that are too network-dependent for the public SDK's normal test suite.

## Cross-project impact

The April work connected the suite. Carbonyl became the runtime. `carbonyl-agent` became the scripting layer. `carbonyl-fleet` became the multi-session service path. `carbonyl-fingerprint-corpus` became the data foundation for persona consistency. `carbonyl-agent-qa` became the place for live-site and trusted-input checks. That split let each project have a clear job.

## Known issues & open threads

The April stack was still early. Linux x86 was the main runtime path. macOS and arm64 support were not yet fully shipped. The trusted-input path needed more real-environment work. The fingerprint corpus and persona work were foundations, not yet a finished public workflow. The X-mirror path was opt-in and meant for operators who needed visual capture.

## What's next

May's work needed to turn the foundation into usable automation features. The obvious next steps were better cookie persistence, stronger text extraction, more runtime variants, a clearer install story, and a richer persona system for agent traffic that should look consistent across browser and network paths.

## Appendix

- **Published packages:** Carbonyl runtime release assets; `carbonyl-agent` package work began in its own repo.
- **Releases:** Carbonyl `v0.2.0-alpha.1` and `v0.2.0-alpha.3`.
- **Source / docs:** github.com/jmagly/carbonyl · github.com/jmagly/carbonyl-agent · github.com/jmagly/carbonyl-fleet · window: April 2026.
