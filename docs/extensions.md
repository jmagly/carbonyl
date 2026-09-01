# Unpacked Manifest V3 extensions

Carbonyl's first extension runtime is deliberately opt-in and local-only. It
supports unpacked Manifest V3 content scripts, extension pages, service
workers, one-off and port messaging, `storage.local`, declared HTTP/HTTPS/file
host permissions, and static `declarativeNetRequest` rules.

Pass the same ordered set of absolute canonical directories to both standard
Chromium switches:

```text
--load-extension=/absolute/path/to/extension
--disable-extensions-except=/absolute/path/to/extension
```

No extension is loaded when those switches are absent. A mismatch, duplicate,
missing/noncanonical directory, symlink anywhere in the extension tree,
malformed manifest, unsupported manifest/type, invalid DNR ruleset, or policy
denial terminates startup with a `CARBONYL_EXTENSION_ERROR code=...` diagnostic.
The runtime also rejects manifest update URLs, unsupported API permissions, and
host permissions outside HTTP(S). The initial permission surface is limited to
`storage`, `declarativeNetRequest`, and
`declarativeNetRequestWithHostAccess`; additional APIs require an explicit
reviewed implementation rather than inheriting Chromium's full registry.

Successful loads emit one privacy-limited `CARBONYL_EXTENSION_DIAGNOSTIC` line
containing the extension ID, version, a SHA-256 of the canonical source path,
manifest SHA-256, initial worker state, API permission names, and the host
permission count. Diagnostics never include the source path, host patterns,
cookies, extension-storage values, page content, or profile secrets.

## Security and profile behavior

- The paired switches are the operator's explicit grant of the permissions in
  the local manifest. Chromium still enforces the resulting API and host
  `PermissionSet` in browser and renderer processes.
- Renderer sandboxing and site isolation remain enabled. Extension content
  scripts execute in isolated worlds beginning at world ID 1.
- Preferences, `storage.local`, DNR state, dynamic user scripts, and service
  worker registrations are owned by the selected browser profile. They persist
  across orderly restarts and do not cross profile directories.
- Carbonyl does not scan profiles or session archives for extensions and does
  not install remote, Web Store, external-provider, component, or CRX content.
- Extension source trees must be writable when they declare static DNR rules,
  because Chromium M150 creates its reserved `_metadata` ruleset index there.

## Unsupported surfaces

Toolbar/action UI, permission prompts, popup/options hosting, and live
load/disable/remove management belong to issue `#290`. Until those Carbonyl UI
surfaces exist, APIs that require them are unavailable. Native messaging,
browser/device restart, background update checks, uninstall-page navigation,
Chrome/Web Store URLs, privileged `chrome://` scripting, component resources,
and automatic reload/update are denied or return an unavailable result. No
Chrome toolbar or Web Store compatibility is implied.

## Acceptance environment

Browser, CDP, display, input, and GPU tests must not run on the Titan build
host. `scripts/test-extension-runtime-integration.sh` refuses to execute unless
it is inside the disposable Ubuntu 26.04 browser-QA guest, explicitly marked
with `CARBONYL_DISPOSABLE_BROWSER_QA=1`, using guest-local Xorg `:99`, with no
Wayland display socket. Ubuntu 26.04 is the runtime acceptance baseline;
Ubuntu 24.04 remains the package compatibility floor.
