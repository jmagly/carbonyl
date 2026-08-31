# Acknowledged persistent-profile shutdown

Carbonyl keeps its historical synchronous shutdown path when no explicit
`--user-data-dir` is active. Persistent profiles use a bounded browser-UI
sequence instead:

1. enter `draining` and reject new page creation, navigation, resize, and input;
2. close every owned `HeadlessWebContents` on the UI sequence;
3. enumerate every loaded `StoragePartition` in every browser context;
4. call `StoragePartition::Flush()` and wait for each cookie manager's
   `FlushCookieStore()` callback;
5. after all callbacks or a 10-second timeout, enter `destroying`, destroy the
   browser contexts and their services, then enter `stopped`;
6. emit one machine-readable result line.

The output contract is a single stderr line with this prefix and JSON schema:

```text
CARBONYL_STORAGE_FLUSH_RESULT={"schema_version":1,"state":"stopped","result":"complete","partitions":1,"acknowledged":1,"token":""}
```

`result` is one of `complete`, `timed_out`, or `failed`. Only `complete` proves
that every loaded partition's cookie-store callback arrived. The generic
storage flush itself has no completion callback in Chromium 150. A Mojo
disconnect that drops a callback therefore reaches the explicit `timed_out`
result; it is never inferred to be successful from process exit.

The line contains only lifecycle counts, states, and an ephemeral random token.
It never contains a URL, cookie, storage key/value, profile path, page content,
or extension data. Callers must also wait for process exit before releasing
their external profile lease, because the line is emitted after BrowserContext
destruction but before the browser main loop quits.

Supervisors that use this line as a lease transition proof must generate a
fresh 128-bit lowercase hexadecimal token for every launch and pass it as
`--carbonyl-storage-flush-token=<token>`. Carbonyl echoes only a valid token in
the result. Requiring an exact match prevents page-rendered terminal text from
masquerading as a shutdown acknowledgement if the runtime crashes before it
can emit the real line. Direct/manual launches that omit the switch receive an
empty token and may use the line for diagnostics, but not as an authenticated
profile-lease proof.

Repeated shutdown requests are idempotent. Attempts to create a page or send
new page work after draining begins are refused with a stable
`CARBONYL_LIFECYCLE_ERROR code=draining operation=<kind>` diagnostic.

## Rebase-sensitive hooks

Patch 0038 extends Chromium 150.0.7871.47 at these ownership boundaries:

- `HeadlessBrowserImpl::Shutdown()` starts the barrier instead of immediately
  clearing `browser_contexts_` for persistent profiles;
- `HeadlessBrowserContextImpl::CreateWebContents()` rejects page creation after
  drain begins;
- the Carbonyl input/navigation entry points reject work while draining;
- `headless_browser` depends on `//carbonyl/src/browser:storage_flush`.

Rebases must confirm that BrowserContext destruction still closes WebContents,
calls `ShutdownStoragePartitions()`, destroys keyed services, and precedes the
main-loop quit closure.
