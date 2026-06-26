# Issue #160: Amazon Regional Product Text Diagnostic

Upstream `fathyb/carbonyl#19` reported that Amazon US product pages rendered
text, while Amazon France/Germany product pages showed almost no visible text in
Carbonyl. The original report was against live Amazon product URLs, so this
harness is intentionally diagnostic rather than a deterministic unit test.

The harness runs each URL with an isolated Chromium profile and captures three
signals:

- `--dump-text` / `document.body.innerText`
- `--dump-text=raw-dom`
- terminal-mode PTY output with ANSI/control sequences stripped

This separates three failure classes:

- DOM text is empty: navigation, bot wall, locale, TLS, or JavaScript gating.
- DOM text exists but terminal text is empty: terminal paint/text-render bug.
- Both contain text: issue is not reproduced for that URL/runtime.

## Usage

```sh
test/repro/issue-160/run.sh
```

Set `CARBONYL_BIN` to test a specific runtime. By default the script uses the
repo prebuilt runtime for the local platform.

Optional environment variables:

- `ISSUE160_URLS`: whitespace-separated URLs to probe.
- `ISSUE160_TIMEOUT`: per-command timeout in seconds, default `45`.
- `ISSUE160_IDLE_MS`: `--dump-text` idle window, default `5000`.
- `ISSUE160_CAPTURE_SECONDS`: terminal capture duration, default `12`.
- `ISSUE160_CHROMIUM_ARGS`: extra Chromium/Carbonyl args appended to every
  launch, for example `--ignore-certificate-errors --lang=fr-FR`.
- `ISSUE160_KEEP_ARTIFACTS=1`: retain the temporary profile/output directory
  for manual inspection.

Default URLs are the upstream report pair:

- `https://www.amazon.com/dp/B09TTDRXNS`
- `https://www.amazon.fr/dp/B0B14J2RJ3`

The script exits `0` when diagnostics were collected. Treat the printed
classification table as the result; live Amazon behavior is not stable enough
for a hard CI pass/fail assertion.
