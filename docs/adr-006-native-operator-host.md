# ADR-006: Carbonyl-owned Views/Aura operator host

- Status: accepted for an experimental spike; production rollout deferred
- Date: 2026-08-31
- Decision owners: Carbonyl maintainers
- Tracks: #285; parent #283

## Context

Carbonyl currently uses Chromium's `headless_shell` embedder. It needs an
interactive native X11 operator window without replacing its terminal output,
copying a profile between browser contexts, or adopting the full Chrome UI.
The capture-only X mirror from #282 is useful for pixels but cannot be the
browser's input host: it is an independent Xlib window and is not in the
`WebContents` Aura hierarchy.

The Chromium baseline for this decision is 150.0.7871.47.

## Current ownership and rendering path

`HeadlessShell::OnBrowserStart` builds the sole `HeadlessBrowserContext`, makes
it the default context, and builds one `HeadlessWebContents`. The corresponding
`HeadlessWebContentsImpl` owns the actual `content::WebContents`, its synthetic
`HeadlessWindow`, and its `HeadlessWindowTreeHost`.

On Aura builds, `HeadlessPlatformDelegate::InitializeWebContents` creates the
headless tree host, parents `WebContents::GetNativeView()` below its root, and
sizes both the native view and root. `HeadlessWindowTreeHost` deliberately has
no accelerated widget, refuses platform-event dispatch, and makes show/hide a
no-op. Carbonyl globally replaces the compositor software output device: each
damage frame is delivered to `LayeredWindowUpdater`, which feeds the terminal
renderer and, when requested, an X11 pixel target.

Shutdown ownership remains with `HeadlessBrowserImpl`. Its browser-context map
owns the contexts; context teardown closes WebContents and shuts down storage
partitions. Today that teardown does not provide the explicit, bounded storage
flush acknowledgement required for a profile lease handoff. That prerequisite
is tracked by #292 and agent #136 rather than being hidden inside the window
prototype.

## Decision

Use a Carbonyl-owned, explicitly feature-gated Views/Aura desktop widget as the
milestone-1 operator host. Reparent the existing `WebContents` native Aura view
through `views::WebView`; do not create a second `BrowserContext` or copy
session data.

The prototype switch is:

```text
--carbonyl-operator-window
```

It is supported only by a Linux runtime built with Ozone X11 and must be used
with `--ozone-platform=x11`. The canonical headless build retains a stub that
fails with an actionable diagnostic if the switch is requested. With no switch,
the existing terminal/headless path is byte-for-byte unchanged at runtime.

The widget uses `DesktopNativeWidgetAura` and a process-lifetime
`wm::WMState`/`ViewsDelegate` scoped ahead of the widget. Operator mode installs
`aura::ScreenOzone`; retaining `HeadlessScreen` while constructing a real
platform window recursively queried its own synthetic bounds. The default path
continues to install `HeadlessScreen`. `views::WebView` moves
`WebContents::GetNativeView()` from the synthetic headless root to the desktop
widget root. The `HeadlessWebContentsImpl` remains the WebContents owner.

Only the browser process uses Ozone X11. Chromium child command lines inherit
the browser's Ozone switch, so `HeadlessContentBrowserClient` replaces that
switch with the headless backend before launching renderer, utility, and GPU
children. Without this split, the headless GPU main loop attempted to construct
an X11 event watcher without a UI message pump. Process separation remains
enabled; the prototype does not use `--single-process`.

Carbonyl's display client now receives its real `ui::Compositor`, preserving
the accelerated widget instead of replacing it with
`gfx::kNullAcceleratedWidget`. Before the widget attaches, the synthetic
headless compositor owns output. Reparenting makes the widget compositor the
page compositor, so ownership then changes atomically: stale synthetic damage
is acknowledged but suppressed, while widget damage is sent to both consumers.

```text
same WebContents / current owner compositor frame
             |
   CarbonylSoftwareOutputDevice
        /                 \
terminal Renderer     Views-owned X11 widget
```

The second leg copies the same shared software raster into the Views widget XID.
Views/Aura and Ozone remain responsible for window lifetime, focus, and physical
event delivery. The Xlib helper does not select or consume events on an
embedder-owned widget.

## Geometry contract

For the spike, the Carbonyl renderer size is the initial source of truth for
the browser viewport and initial native content bounds. Device scale remains
the existing Carbonyl/HeadlessScreen value. `WebView` owns Aura reparenting and
content bounds inside the widget. The terminal renderer samples the same
physical compositor raster.

Production resize, monitor-scale changes, terminal cell mapping, and
trusted-input coordinate transforms are assigned to #287. Browser-owned
control insets and their unspoofable committed-origin display are assigned to
#288. Both issues preserve one transform rather than let the native widget,
terminal renderer, and uinput path maintain independent geometry.

## Profile and lifecycle contract

Operator and headless modes use one canonical user-data directory, but never at
the same time. No milestone-1 code may clone cookies or Web Storage into a
second context.

The production handoff sequence is:

1. hold the cross-process profile lease;
2. stop accepting new page work;
3. close/drain WebContents;
4. receive the bounded storage-partition and cookie-store flush result from
   #292;
5. destroy the BrowserContext and release its Chromium profile lock;
6. release the external lease;
7. acquire the lease in the next mode and open the same canonical directory.

Agent #136 owns that state machine, stale-owner recovery, and PID-reuse-safe
lease metadata. QA #37 owns operator/headless round trips, crash recovery,
lock contention, timeout paths, and latency percentiles using synthetic local
fixtures only.

## Alternatives considered

### `content_shell`

It is the closest reference implementation: its Views delegate constructs a
desktop widget and its `ShellView` hosts an existing `WebContents` in a
`WebView`. Adopting the full executable would duplicate Carbonyl's headless
startup, command handlers, renderer bridge, and packaging. We reuse the small
hosting pattern instead.

### `extensions/shell`

It offers extension-oriented embedder machinery but adds an application model,
extension UI assumptions, and a larger rebase surface before M1 needs them.
The M150 extension capability decision is recorded separately in ADR-005.

### Full Chrome browser embedder

This supplies standard Chrome UI and the broadest extension surface, but its
dependency, binary, policy, profile, and rebase cost are disproportionate to a
single-window M1 operator. Selecting it would also make claims about Chrome UI
and Web Store compatibility that Carbonyl cannot presently support.

### X mirror as the operator window

Rejected. A raw copy window can prove pixel availability, but it has no hosted
`WebContents`, Aura focus chain, IME, accessibility parent, or Chromium input
dispatch. Keeping it as the input surface would perpetuate the exact split the
operator project is intended to remove.

## Build and rebase impact

The default headless GN graph adds only Carbonyl's unsupported-platform stub.
The X11 build adds direct dependencies on `//ui/aura`, `//ui/views`,
`//ui/views/controls/webview`, and `//ui/wm`; it does not depend on Chrome,
content_shell, extensions shell, or Views test support. The Chromium patch
surface is one additive patch touching six upstream files: the `headless_shell`
deps list and startup hook, browser-child switch propagation, operator-only
ScreenOzone selection, the Carbonyl display-client constructor call, and
`HeadlessShell` ownership of the operator host. All substantive widget and
dual-output implementation remains below `//carbonyl/src/browser`.

The 2026-09-01 M150 measurement found 10,105 transitive GN targets in the
headless graph and 10,200 in the X11/operator graph: 95 additional targets, or
0.94%. The `operator_window` target itself has 8,821 transitive dependencies in
headless-stub mode and 8,917 in X11 mode. Its four additional direct
dependencies are exactly Aura, Views, Views WebView, and WM.

GNU `strip` produced a 983,997,584-byte headless baseline and a
990,465,168-byte X11/operator binary. The measured increase is 6,467,584 bytes
(0.657%). The headless executable predates the final lifecycle additions, so
this is a conservative upper bound for the operator-only size delta rather than
an estimate that understates it.

Wall-clock rebuild time is not a graduation metric. Ninja 1.13 invalidated the
existing v5 build log and scheduled 39,741 actions despite reusable outputs. An
unbounded run drove the interactive build host to load 107 and only 6.1 GiB of
available memory, reproducing the resource-risk signature tracked by #299; it
was interrupted without deleting outputs and later work was capped. That time
would measure log migration, cache state, and concurrency rather than this
architecture. The exact GN target delta and stripped bytes above are the
reproducible build-impact measures.

## Prototype validation

The M150 X11 `headless_shell` linked successfully with the feature enabled. The
final multiprocess acceptance ran in a disposable Ubuntu 26.04.1 KVM guest on
guest-local Xorg `:99`, with no host display socket or input-device access and
with Chromium's sandbox enabled through a path-scoped AppArmor user-namespace
profile. It produced the fixture's initial native red/blue pixels, the same
page's terminal raster, a green transition after a trusted pointer event, and a
gold transition after trusted keyboard delivery. The same run then passed an
operator -> acknowledged drain -> headless -> acknowledged drain -> operator
profile round trip and three consecutive trusted-input cycles. The tested X11
runtime source key is `edece3812b017689`; its 300,958,052-byte archive has
SHA-256 `5ad3a4d30140977593bb611b839a50fd7e6bdf8e65c38cc64bf38212826a91ee`.

## Security consequences

- Chromium sandboxing and site isolation remain enabled.
- The operator switch does not imply `--no-sandbox`.
- There is one BrowserContext and one WebContents; no credential-bearing state
  is copied between embedders.
- Physical X11 input reaches the real hosted Aura hierarchy. Trusted uinput
  remains an explicit privileged boundary and must use the #287 coordinate
  model.
- A profile lease is mandatory before daemon/operator mode switching. The
  prototype is not authorization to open one directory concurrently.
- Native-window diagnostics expose only widget IDs and dimensions, never URLs,
  cookies, storage values, or profile contents.
- The browser-owned committed-origin line lives outside the WebView and derives
  only from Chromium navigation/SSL state; page content cannot overlap it or
  supply its text.
- Operator address input allows only browser-navigation schemes. Disallowed
  schemes become escaped HTTPS search text and are never executed as page
  script.

## Consequences and implementation sequence

The spike can prove native hosting, real event delivery, and dual output while
remaining opt-in. It does not by itself claim production-ready resize, browser
controls, or crash-safe profile handoff.

The #286 implementation exposes the same selected architecture as the
X11-only GN executable target
`//carbonyl/src/browser:carbonyl_operator_shell`. The small Carbonyl-owned
launcher adds `--carbonyl-operator-window` and then replaces itself with the
sibling `headless_shell` through `execv`. The resulting browser process is the
existing shell: it owns the same one BrowserContext/WebContents and follows the
already-tested operator startup path. A GN `data_deps` edge ensures the sibling
shell is built first. There is no second Chromium link product, the existing
`//headless:headless_shell` target is not refactored, and default packaging does
not depend on the new target. Building the experiment adds only the small
launcher ELF; it adds zero bytes to the packaged runtime unless a future
release explicitly opts it in.

The selected design decomposes as follows:

- #286: isolated experimental operator shell and dual-output smoke evidence;
- #287: geometry, resize, focus, XKB/IME, pointer, and trusted input;
- #288: Carbonyl-owned navigation and trustworthy origin controls;
- #292: acknowledged BrowserContext storage flush and orderly shutdown;
- agent #136: canonical profile lease and cross-mode state machine;
- QA #37: round-trip, crash, lock, timeout, and performance matrix.

Production integration into parent #283 remains gated on those results.

## References

- Chromium M150 `content/shell/browser/shell_platform_delegate_views.cc`
- Chromium M150 `headless/lib/browser/headless_platform_delegate_aura.cc`
- Chromium M150 `headless/lib/browser/headless_window_tree_host.cc`
- Chromium M150 `ui/views/controls/webview/webview.cc`
- #282, #283, #285, #286, #287, #288, #292; agent #136; QA #37
