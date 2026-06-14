# Carbonyl v0.2.0-alpha.5

M148 maintenance release with a green runner-host build and release pipeline.

## Highlights

### Chromium M148 baseline

Carbonyl now tracks Chromium `148.0.7778.167`. The Chromium patch stack was
regenerated against the M148 base commits and now contains 26 patches.

The M148 rebase keeps the existing Carbonyl architecture intact while carrying
the required API-drift updates in compositor/debug dump code and the terminal
render paint path.

### Runner-host CI repairs

The runtime workflow now prepares the persistent titan checkout before every
build:

- syncs `chromium/src` to the `.gclient` pin before applying patches
- normalizes ownership of Carbonyl-owned host files before rsync
- avoids preserving owner/group metadata during rsync
- keeps the large Chromium checkout and depot_tools tree persistent

The GitHub mirror workflow now computes the remote ref SHA and uses an explicit
force-with-lease for branch updates, which avoids stale-info failures from a
fresh mirror clone.

### X11 runtime validation

The x11 smoke test captures Carbonyl through a real PTY via `script` and checks
both outputs before publishing the runtime:

- terminal ANSI raster output
- X framebuffer screenshot output

This prevents the release workflow from packaging an x11 runtime unless the
terminal and X-mirror paths both render the expected fixture.

## What's in the runtime

amd64, both Ozone variants (runtime hash `8f070d2720157bd0`):

- `carbonyl-0.2.0-alpha.5-x86_64-unknown-linux-gnu.tgz` - `headless` ozone (default; pure-terminal)
- `carbonyl-0.2.0-alpha.5-x11-x86_64-unknown-linux-gnu.tgz` - `x11` ozone (terminal + X-mirror; for trusted-input mode)

Each tarball ships with a `.sha256` companion.

## Verification

- `build-runtime.yml` run 133: `headless` amd64 and `x11` amd64 succeeded.
- `mirror.yml` run 134 succeeded.
- The final x11 validation captured terminal output, found 4,351 quadrant block
  runs, and passed the framebuffer pixel-histogram check.
