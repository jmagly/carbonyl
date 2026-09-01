# ADR-005: M150 extension support is a Carbonyl-owned embedder layer

**Date:** 2026-08-30

**Status:** Accepted; fail-closed client linkage and opt-in unpacked MV3 runtime implemented

**Related:** Carbonyl `#156`, `#285`, `#289`, `#290`

## Context

Carbonyl is built from Chromium's `//headless:headless_shell` target. Chromium
150.0.7871.47 compiles the core extensions module on desktop by default, but
the headless shell does not link or initialize that module. The older
`//extensions/shell` sample embedder is not present in the pinned M150 tree.
Enabling the GN build flag alone therefore cannot make extensions work.

The M150 extension module is deliberately embedder-facing:

- `ExtensionsClient` owns process-global common initialization.
- `ExtensionsBrowserClient` supplies browser-process policy and services.
- `ExtensionsRendererClient` supplies renderer initialization and frame hooks.
- `ExtensionSystem` owns per-`BrowserContext` extension services and their
  lifecycle.

Chrome implements those interfaces through its `Profile` and browser UI. That
implementation cannot be reused by `HeadlessBrowserContextImpl`: it assumes
Chrome's `ProfileManager`, profile-keyed factories, UI delegates, policy
services, and shutdown ordering. Pulling `//chrome` into headless shell would
also turn a narrow integration into a second browser product surface.

## Decision

Implement extension support as a thin, Carbonyl-owned embedder layer over the
public `//extensions` module. Do not link Chrome's extension implementation and
do not revive the removed extension shell.

The layer is split into three explicit process surfaces:

1. **Common:** install one Carbonyl `ExtensionsClient` before content process
   startup and register only the core MV3 API/manifest providers required by
   the accepted milestone.
2. **Browser:** install one Carbonyl `ExtensionsBrowserClient` before creating
   any `HeadlessBrowserContextImpl`; create a Carbonyl `ExtensionSystemProvider`
   and build all required browser-context keyed service factories before the
   context is marked live.
3. **Renderer:** install one Carbonyl `ExtensionsRendererClient`; forward
   `RenderThreadStarted`, `RenderFrameCreated`, and extension frame/service
   worker interface binders from the headless content clients.

The browser layer will be placed under `chromium/src/carbonyl/src/extensions/`
and linked into the existing headless targets. Chromium patch files should
contain only the small headless hook and GN dependency changes. This keeps
upstream rebase conflicts at the boundary instead of distributing Carbonyl
policy across `//headless` and `//extensions`.

## Security and lifecycle invariants

- Extensions remain disabled by default. Runtime activation requires the
  explicit operator configuration designed in `#289`.
- Milestone 1 accepts unpacked MV3 directories only. Store installation,
  external providers, update URLs, CRX installation, native messaging, and
  arbitrary component extensions stay unavailable.
- Paths are canonicalized before browser startup. Symlinks, missing files,
  non-directories, and manifests outside the canonical root fail closed.
- Permission and host-access decisions are made by the browser process. The
  renderer never upgrades an extension's authority.
- The active `BrowserContext` owns extension prefs, state stores, service
  workers, and declarative rules. No extension state is placed in Carbonyl's
  process-global singleton objects.
- `ExtensionsBrowserClient::StartTearDown()` runs before the context begins
  destruction. Extension services stop before
  `DestroyBrowserContextServices()` and before the profile lease is released.
- Diagnostics expose only extension ID, declared version, canonical path, and
  source-tree hash. They do not emit extension storage, page data, cookies, or
  requested secrets.
- The profile-continuity and storage-flush contract is supplied by `#285`.
  Extension preferences, API storage, DNR rules, and user-script state are
  profile-owned and are torn down before the profile lease is released.

## Build slices

The implementation should land in independently testable slices:

1. **Implemented in patch 0039:** link core `//extensions`
   common/browser/renderer targets into headless shell and install fail-closed
   Carbonyl clients while keeping extension loading disabled.
2. **Implemented in patch 0040:** create the profile-owned `ExtensionSystem`,
   state stores, service-worker and user-script managers, scheme/factory/frame
   hooks, and isolated-world renderer dispatcher.
3. **Implemented by `#289`:** require identical canonical
   `--load-extension` and `--disable-extensions-except` paths; reject symlinks,
   malformed manifests, non-MV3 types, and remote/update installation; index
   DNR rules and grant only the extension's declared API and host permissions.
4. Add live management/action surfaces from `#290` only after runtime
   semantics and browser-owned controls are stable.

The Carbonyl-owned implementation lives under `src/extensions/`; patches 0039
and 0040 connect its fail-closed client linkage and opt-in runtime hooks to
Headless. `scripts/audit-extension-embedder.sh` runs against the applied patch
stack and proves the no-Chrome boundary, default-deny activation, profile-owned
services, dedicated extension-process policy, worker/frame binders, DNR proxy,
and renderer lifecycle seams. This completes the fail-closed linkage slice of
`#156` and the unpacked runtime slice of `#289`; live controls remain in `#290`.

`scripts/audit-extension-embedder.sh` records the current M150 baseline and
fails when an upgrade invalidates one of the source or build assumptions used
by this decision. `scripts/test-extension-runtime-contract.sh` validates the
opt-in contract and committed MV3 content-script, worker, messaging,
`storage.local`, and DNR fixture.

## Rejected alternatives

### Set `enable_extensions=true` only

Rejected. It is already true for the pinned desktop build. The flag makes the
module buildable; it does not install clients, construct an `ExtensionSystem`,
or forward browser/renderer hooks.

### Reuse Chrome's extension stack

Rejected. It is coupled to `Profile`, Chrome browser-process services, UI, and
policy. Importing it would greatly expand binary size and the maintenance and
security surface.

### Restore `//extensions/shell`

Rejected. The sample is absent in M150 and its historical app-shell policy is
not Carbonyl's threat model. Carbonyl still needs its own profile, permissions,
diagnostics, and operator-control decisions.

## Consequences

- Extension support is a real embedder project, not a command-line switch.
- Default startup remains extension-free; activation is an explicit paired
  command-line decision.
- M150 upgrades get a small set of auditable integration hooks and a scripted
  source-surface check.
- Persistent extension functionality uses the accepted profile lifecycle and
  stays isolated by `BrowserContext` and profile path.

## Upstream references (Chromium 150.0.7871.47)

- [`extensions/buildflags/buildflags.gni`](https://chromium.googlesource.com/chromium/src/+/refs/tags/150.0.7871.47/extensions/buildflags/buildflags.gni)
- [`extensions/common/extensions_client.h`](https://chromium.googlesource.com/chromium/src/+/refs/tags/150.0.7871.47/extensions/common/extensions_client.h)
- [`extensions/browser/extensions_browser_client.h`](https://chromium.googlesource.com/chromium/src/+/refs/tags/150.0.7871.47/extensions/browser/extensions_browser_client.h)
- [`extensions/browser/extension_system.h`](https://chromium.googlesource.com/chromium/src/+/refs/tags/150.0.7871.47/extensions/browser/extension_system.h)
- [`extensions/renderer/extensions_renderer_client.h`](https://chromium.googlesource.com/chromium/src/+/refs/tags/150.0.7871.47/extensions/renderer/extensions_renderer_client.h)
- [`headless/BUILD.gn`](https://chromium.googlesource.com/chromium/src/+/refs/tags/150.0.7871.47/headless/BUILD.gn)
- [`headless/lib/browser/headless_browser_context_impl.cc`](https://chromium.googlesource.com/chromium/src/+/refs/tags/150.0.7871.47/headless/lib/browser/headless_browser_context_impl.cc)
- [`headless/lib/renderer/headless_content_renderer_client.cc`](https://chromium.googlesource.com/chromium/src/+/refs/tags/150.0.7871.47/headless/lib/renderer/headless_content_renderer_client.cc)
