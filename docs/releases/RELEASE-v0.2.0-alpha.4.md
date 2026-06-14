# Carbonyl v0.2.0-alpha.4

Single-feature release: opt-in eager cookie persistence for automation
harnesses that need to call `close()` shortly after a session sets cookies.

## Highlights

### `--carbonyl-cookie-flush-interval-ms=N` — opt-in eager cookie SQLite flush

Chromium's network service flushes its on-disk cookie store every 30 s
(`kCommitInterval` in `SQLitePersistentCookieStore::Backend::BatchOperation`).
Test/automation callers had to drain ≥ 30 s before `close()` to avoid losing
cookies set during the session — empirically:

| pre-close drain | cookie persisted? |
|---|---|
| 5–20 s | ❌ |
| 30 s   | ✅ |
| 35 s   | ✅ |

This release adds an opt-in CLI override:

```sh
carbonyl --carbonyl-cookie-flush-interval-ms=2000 https://example.com
```

With `2000`, the network-service commit interval drops to 2 s, so a 5 s
drain before SIGTERM is sufficient. Default behavior is unchanged for
non-automation users — no perf or IO regression on normal browsing.

The switch is forwarded from the browser process to the network service
utility process via `HeadlessContentBrowserClient::AppendExtraCommandLineSwitches`
(without the forward, the switch was silently no-op'd because the cookie
store lives in a separate process).

Closes [#69](https://github.com/jmagly/carbonyl/issues/69).

## What's in the runtime

amd64, both Ozone variants (runtime hash `9b3ba53adcd8d330`):

- `carbonyl-0.2.0-alpha.4-x86_64-unknown-linux-gnu.tgz` — `headless` ozone (default; pure-terminal)
- `carbonyl-0.2.0-alpha.4-x11-x86_64-unknown-linux-gnu.tgz` — `x11` ozone (terminal + X-mirror; for trusted-input mode)

Each tarball ships with a `.sha256` companion.

## Changelog

See [`changelog.md`](https://github.com/jmagly/carbonyl/blob/v0.2.0-alpha.4/changelog.md)
for the full entry covering this and prior CI/parity work.
