---
title: "Carbonyl suite — May 2026 Report"
slug: "2026-5-carbonyl-may-2026-report"
date: "2026-05-31"
project: "carbonyl"
type: report
tags: [report, "2026-05", "carbonyl", "browser-automation"]
summary: "May turned the Carbonyl suite from a fresh maintained fork into a useful browser toolchain: M148 landed, text output grew, the SDK gained profiles and cookie import, and the QA stack made trusted input clearer."
reading_time: 10
status: "published"
pillar: "1 report"
audience: "Carbonyl users and evaluators who want the May 2026 release summary"
---

# Carbonyl suite — May 2026

*Carbonyl is a real web browser that runs inside your terminal. Around it, the suite adds a Python SDK, a fleet server, browser-profile tools, and QA tools. This report covers our maintained suite work for May 2026.*

## TL;DR

May was the month Carbonyl moved from "the fork builds" to "the stack is useful for agents." The browser moved to Chromium M148. It added better cookie saving for scripts, a text-dump mode, and cleaner terminal output. The SDK gained durable profiles, matching network calls, host-browser cookie import, and a clearer release line. The QA work also became more honest. Some trusted-input tests need a VM or host setup when Docker cannot provide the right devices.

## By the numbers

| What's public | Value |
|---|---|
| Browser release line | `v0.2.0-alpha.4`, `v0.2.0-alpha.5`, `v0.2.0-alpha.6`, `v0.2.0-alpha.7` |
| SDK release line | `v0.1.0a1`, `0.2.0a1`, `2026.5.0`, `2026.5.1`, `2026.5.2`, `2026.5.3` |
| Browser baseline | Chromium M148 for the May runtime line |
| New browser capabilities | Cookie flush control, text dump, accessibility output, cleaner terminal rendering, macOS Apple Silicon build path |
| New SDK capabilities | Durable browser profiles, matching network calls, offline install, cookie import, QA-runner guidance |
| Browser profile data | Chrome, Firefox, Safari, Android, and iOS reference data seeded across the SDK and corpus work |
| Public source | github.com/jmagly/carbonyl · github.com/jmagly/carbonyl-agent |

## Highlights

**1. Cookie saving became script-friendly.**
What it is: Carbonyl added a flag that can flush Chromium cookies to disk more quickly.
How you'd use it: log in, wait a few seconds, close the browser, then reuse the same session.
Why it helps: scripts no longer need to wait for Chromium's normal longer cookie flush window before shutdown.

**2. The browser moved to Chromium M148.**
What it is: the maintained fork advanced to the next Chromium baseline.
How you'd use it: keep running the same Carbonyl commands, but on a fresher browser engine.
Why it helps: modern sites move fast. A current browser base reduces compatibility drift.

**3. Text output became a first-class mode.**
What it is: `--dump-text` loads a page and prints useful text without starting the visual terminal renderer.
How you'd use it: ask Carbonyl to fetch a page for a scraping job or an agent prompt, then pipe the text to another tool.
Why it helps: agents often need page content, not a live terminal display. This mode gives them that directly.

**4. Terminal rendering got easier to read.**
What it is: flat page regions render more cleanly, the browser can lay pages out to match the sample window, and the URL bar can use more than one row.
How you'd use it: run Carbonyl in a wide terminal or a scripted viewport and get a more stable view.
Why it helps: the browser becomes easier to inspect by eye and easier to test.

**5. The SDK gained durable browser profiles.**
What it is: a profile can now drive both the browser and the matching network client.
How you'd use it: run a browser as one realistic client, then make API calls that match it.
Why it helps: scripts look less split-brained. The browser and network path agree about what kind of client they are.

**6. Host-browser cookie import landed.**
What it is: `carbonyl-agent` can import cookies from a host browser into a Carbonyl session with user approval and redacted logs.
How you'd use it: move an already logged-in session into Carbonyl when an interactive login is hard to script.
Why it helps: you can reuse legitimate local browser state without exposing cookie values in logs.

## Features shipped

**Cookie flush control in the browser.** Carbonyl added `--carbonyl-cookie-flush-interval-ms=N`. Chromium normally writes cookie changes on its own schedule. That is fine for a person browsing. It is awkward for scripts that close soon after login. The new flag lets scripts shorten that wait. Normal browsing stays unchanged.

**Chromium M148 runtime.** The browser advanced to Chromium M148. This was care-and-feeding work, but it matters. Modern sites expect a current browser. The patch stack stayed intact, and releases kept shipping terminal-only and X11 builds.

**Headless text output.** The May browser line added `--dump-text`, with structured and raw page options. In plain terms, Carbonyl can now act as a page-to-text tool. It loads a real page with Chromium, waits for it, and prints text for scripts, search, or model input. Later months built on this, but May made the mode real.

**Better render controls.** The browser fixed speckle in near-flat color areas by drawing them as one color. It also made terminal layout line up better with the sampled window. `--chrome-rows=N` lets the URL bar use more than one row. These are small features, but they make Carbonyl feel less like a demo and more like a tool you can use.

**Mac build path.** May added a clear Apple Silicon macOS build path. This did not solve every Mac packaging task, but it proved the browser could build on Apple Silicon with documented steps.

**Durable profiles in the SDK.** `carbonyl-agent` added profile-based browser state that is separate from simple named sessions. A profile can keep its own state, can be exported or imported, and cannot be opened twice by accident. This gives agent workflows a cleaner way to manage repeatable browser identities.

**Matching network calls.** The SDK added a network client that can match the same profile as the browser. That lets browser traffic and API traffic tell the same story. It also added an audit trail that records behavior without dumping secret values.

**Browser profile data and checks.** The fingerprint work seeded templates and reference data for Chrome, Firefox, Safari, Android Chrome, and iOS Safari paths. It also added checks that compare expected network behavior with captured behavior. The user-facing point is simple: realistic scripts need consistency across many surfaces.

**Cookie import in the SDK.** The SDK added commands to import, list, and revoke cookies from host browsers. It asks per domain. It refuses sensitive domains unless the user confirms. It reads source data safely, writes files with tight permissions, and redacts cookie values from the audit log.

## Fixes

The browser fixed cookie flush forwarding so the new cookie flag reaches Chromium's network service. It fixed failed page loads in text-dump mode, so they return a clear exit code instead of page noise. It improved terminal and X11 output. It also tightened runtime builds, so releases are less likely to package a broken variant.

The SDK fixed daemon shutdown and profile-mode behavior. It improved CI stability and cleaned up docs around trusted-input limits. The QA runner work made one point clear: Docker is useful for some checks, but real trusted-input flows need a VM or host setup when device registration matters.

## Performance & reliability

May added reliability in several layers. The browser's text-dump mode exits in a more orderly way, so cookies and on-disk state can flush. Runtime builds gained more checks before publish. `carbonyl-agent` added readiness probes, context managers, daemon reconnect behavior, log rotation, and build checks. The fleet server remained the base for supervised multi-browser sessions.

## Breaking changes & migrations

No normal browser CLI migration was required for May's user-facing browser work. The new flags were additive.

The SDK changed its version style during May. It moved from early prerelease numbers to a calendar-based line. Users should follow the documented `carbonyl-agent` release tags and install guide.

## Releases

**Carbonyl `v0.2.0-alpha.4` — May 2026.**
This browser release added opt-in eager cookie saving for scripts that close shortly after login.

**Carbonyl `v0.2.0-alpha.5` — May 2026.**
This release moved the browser to Chromium M148 and repaired the runner-host release path.

**Carbonyl `v0.2.0-alpha.6` — May 2026.**
This release carried the next rendering and CI fixes in the M148 line.

**Carbonyl `v0.2.0-alpha.7` — May 2026.**
This release added the macOS Apple Silicon build path, text-dump output, structured page output, render fixes, URL-bar row control, and more runtime build hardening.

**`carbonyl-agent v0.1.0a1` and `0.2.0a1` — May 2026.**
These early SDK releases exercised the package pipeline and shipped the first broad feature set: sessions, daemon mode, uinput support, profiles, matching network calls, and runtime pinning.

**`carbonyl-agent 2026.5.0`, `2026.5.1`, `2026.5.2`, and `2026.5.3` — May 2026.**
These releases moved the SDK to calendar versioning, refreshed browser profile support, added offline install support, pinned the M148 runtime, and shipped host-browser cookie import.

**Fingerprint corpus `2026-05-18-m148` — May 2026.**
The corpus added Chrome 148 desktop and Android reference data for downstream profile checks.

## Dependencies & security

The SDK added tighter install and audit behavior. Runtime downloads remained checksum-verified. Offline install support gave operators a way to install from a local tarball. Cookie import was designed with clear domain approval, a sensitive-domain guard, copy-then-read database access, redacted audit logs, and strict file permissions. The profile and network-call work also added audit records, so operators can see when a request drifts from the selected profile.

## Docs & developer experience

May improved docs for install paths, sessions, daemon mode, profiles, runtime fit, build needs, and QA-runner modes. The browser docs explained runtime modes and releases. The SDK docs added examples and an API reference path. The QA docs made the Docker versus VM tradeoff plain instead of hiding it.

## Tests & CI

The browser added stronger runtime checks for terminal and X11 builds. Patch checks became part of the workflow. The SDK added unit, type, docs, profile, network, and cookie test paths. The QA repo added host-side trusted-input tests, visual capture checks, runner-image builds, and later a screenshot-audit harness.

## Cross-project impact

May connected the browser and SDK more tightly. The browser's cookie-flush flag made SDK sessions more dependable. The M148 runtime pin kept the SDK and browser aligned. The fingerprint corpus fed profile checks. The QA runner documented where full trusted-input tests should run. Fleet remained the service path for scaling the same browser sessions beyond one script.

## Known issues & open threads

Trusted-input scripts still needed the right environment. Docker alone was not enough for every uinput and Xorg path. PyPI publish was still being staged for parts of the SDK release process. Some profile network behavior still depended on captured fixtures and follow-up browser-family work. Linux x86 was the strongest runtime path, while broader runtime distribution kept maturing.

## What's next

June needed to make the browser easier to install and safer to download, improve real input support, expand text extraction, and keep clearing old browser gaps. The SDK needed to stay aligned with the runtime while keeping the QA path honest about what can and cannot be tested in a container.

## Appendix

- **Published packages:** Carbonyl runtime assets; `carbonyl-agent`; `carbonyl-fingerprint` work inside the SDK; fingerprint corpus release data.
- **Releases:** Carbonyl `v0.2.0-alpha.4`, `v0.2.0-alpha.5`, `v0.2.0-alpha.6`, `v0.2.0-alpha.7`; `carbonyl-agent` May release line; fingerprint corpus `2026-05-18-m148`.
- **Source / docs:** github.com/jmagly/carbonyl · github.com/jmagly/carbonyl-agent · github.com/jmagly/carbonyl-fleet · window: May 2026.
