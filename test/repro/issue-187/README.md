# Issue 187: JavaScript Dialogs

This fixture verifies that page JavaScript dialogs do not block Carbonyl's
headless WebContents.

The expected deterministic policy is:

- `alert()` is acknowledged.
- `confirm()` returns `true`.
- `prompt()` returns the page-provided default text.

After rebuilding the Chromium runtime with patch 0036 applied, run:

```bash
carbonyl --dump-text "file://$PWD/test/repro/issue-187/fixture.html"
```

Expected output contains:

```text
alert:ack
confirm:true
prompt:default-value
```

If JavaScript dialogs are not handled, the page will stall before updating the
`#result` text.
