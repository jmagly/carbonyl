# Security Screening: Operator Zoom and Extensions Center

**Result:** Conditional pass for planning; privileged WebUI requires an implementation gate.

## Assets

- Persistent profile preferences and extension state.
- Operator trust in browser-owned identity/status.
- Browser-process extension-management authority.
- Page, extension, and WebUI process isolation.
- Cookies, local storage, extension storage, source paths, and host patterns.

## Trust boundaries

1. Physical/XTEST keyboard input to native Views accelerators.
2. Ordinary page renderer to browser-owned operator chrome.
3. Extension renderer/content to action/options surfaces.
4. Internal WebUI renderer to narrow browser-process handler.
5. Browser-process management policy to profile-owned prefs and extension system.

## Threats and controls

- **Shortcut injection/leakage:** high-priority exact accelerator matching; handled commands never reach page or extension script.
- **Origin spoofing:** a native trusted header and dedicated registered internal origin; never use page title/content as identity.
- **Privilege escalation through WebUI:** process lock, exact factory registration, typed minimal IPC, browser-side reauthorization, and negative tests from ordinary/extension origins.
- **XSS/markup injection:** bundled resources, strict CSP, text-only DOM updates, no `innerHTML`, sanitized/bounded/bidi-isolated manifest data.
- **Arbitrary source authorization:** basic WebUI cannot accept filesystem paths or discover profile contents; load-unpacked is deferred.
- **Management bypass:** existing `unavailable`, `read-only`, and `restart` modes remain authoritative; no live registry mutation.
- **Sensitive disclosure:** local UI shows only data required for informed control; logs retain current hashes/counts and exclude paths, host patterns, page data, cookies, and stored values.
- **Use-after-free/stale callbacks:** generation-bound Mojo connections, navigation disconnect, weak pointers, and close-before-BrowserContext teardown.
- **Popup/options escape or spoofing:** native sanitized owner identity, same-extension navigation enforcement before commit, default-deny new windows/downloads/dialogs/external handoff, bounded sizing, and deterministic dismissal/focus/teardown.
- **Host instability:** UI QA is prohibited on Titan's host display/Wayland session and the guest launcher fails closed before browser start on any missing isolation signal.

## Required security acceptance

- [ ] WebUI factory cannot bind for any non-approved scheme/host.
- [ ] Internal page receives a dedicated process/origin lock and no ordinary navigation can reuse it.
- [ ] CSP and resource audit show no network, frame, plugin, object, or unsafe-eval access.
- [ ] IPC fuzz/negative tests reject unknown IDs, operations, stale connections, oversized payloads, paths, URLs, and permission objects.
- [ ] All mutation requests re-check mode and profile ownership in browser code.
- [ ] Hostile manifest metadata renders only as bounded visible text.
- [ ] No Web Store, CRX/update, native messaging, remote code, profile scan, or silent source authorization is introduced.
- [ ] Storage flush and teardown remain acknowledged and ordered.
- [ ] The active-page bridge cannot outlive or confuse the primary page, manager, or owning `BrowserContext`.
- [ ] Popup/options identity, navigation, sizing, dismissal, focus restoration, disable/crash, and teardown negative tests pass before the center exposes those entry points.
- [ ] The Ubuntu 24.04/26.04 Xorg launcher requires `CARBONYL_DISPOSABLE_BROWSER_QA=1`, guest-owned `DISPLAY=:99`, no Wayland/host endpoints, and exits nonzero before launch on every failed guard.

## References

- Chromium WebUI explainer: https://chromium.googlesource.com/chromium/src/+/main/docs/webui_explainer.md
- Chrome extension security guidance: https://developer.chrome.com/docs/extensions/develop/security-privacy/stay-secure
- Chrome management API: https://developer.chrome.com/docs/extensions/reference/api/management
- Existing Carbonyl extension boundary: `@docs/adr-005-m150-extension-embedder.md`
