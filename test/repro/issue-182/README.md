# Issue #182 Download Repro

This harness verifies promptless downloads through `--download-dir`.

It starts a local HTTP server with an attachment endpoint, navigates Carbonyl
directly to that endpoint, and checks that the expected file lands in the
configured download directory.

Run:

```sh
test/repro/issue-182/run.sh
```

Exit codes:

- `0` - the file was downloaded with expected content
- `1` - the browser ran, but the expected file was not downloaded
- `2` - harness/runtime setup failed
