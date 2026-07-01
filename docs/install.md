# Installing Carbonyl

Carbonyl ships native install packages in addition to the raw runtime tarballs
and the npm package. Pick the one for your platform. Assets are attached to each
[release](https://github.com/jmagly/carbonyl/releases) (and mirrored on the
Gitea origin).

| Platform | Artifact | Install |
|---|---|---|
| Debian / Ubuntu (x86_64) | `carbonyl_<version>_amd64.deb` | `sudo apt install ./carbonyl_<version>_amd64.deb` |
| Fedora / RHEL / openSUSE (x86_64) | `carbonyl-<version>-1.x86_64.rpm` | `sudo dnf install ./carbonyl-<version>-1.x86_64.rpm` |
| Any Linux (x86_64, portable) | `carbonyl-<version>-x86_64.AppImage` | `chmod +x carbonyl-*.AppImage && ./carbonyl-*.AppImage <url>` |
| macOS (Apple Silicon) | `carbonyl-<version>-macos-arm64.pkg` (in `.dmg`) | open the `.dmg`, run the `.pkg` (see Gatekeeper note below) |

> Prerelease versions appear as `0.2.0~alpha.9` in `.deb`/`.rpm` filenames — the
> `~` is correct Debian/RPM ordering (sorts *before* `0.2.0`).

> **Verifying downloads.** Every asset ships a `.sha256`, an `.md5`, and a detached
> GPG signature `.asc` (signed with the dedicated Carbonyl release key):
> ```bash
> curl -fsSL https://magly.net/keys/carbonyl-release.asc | gpg --import
> gpg --verify carbonyl-<version>-<asset>.asc carbonyl-<version>-<asset>
> sha256sum -c carbonyl-<version>-<asset>.sha256   # md5sum -c …md5 (legacy)
> ```
> See [SIGNING.md](SIGNING.md) for the key fingerprint and full instructions.

After installing, run for example:

```bash
carbonyl https://example.com
```

## Linux: .deb / .rpm

Both install `carbonyl` to `/usr/bin/carbonyl` (a small launcher) with the
runtime under `/usr/lib/carbonyl/`, plus a desktop entry and icon. Dependencies
on the system Chromium runtime libraries (nss, dbus, X11, alsa, drm, gbm, …) are
declared, so the package manager pulls anything missing.

```bash
# Debian / Ubuntu
sudo apt install ./carbonyl_<version>_amd64.deb
# remove:  sudo apt remove carbonyl

# Fedora / RHEL / openSUSE
sudo dnf install ./carbonyl-<version>-1.x86_64.rpm
# remove:  sudo dnf remove carbonyl
```

## Linux: AppImage (no install)

Self-contained, no root required:

```bash
chmod +x carbonyl-<version>-x86_64.AppImage
./carbonyl-<version>-x86_64.AppImage https://example.com
```

If your system lacks FUSE, run with `--appimage-extract-and-run`.

## macOS (Apple Silicon)

Carbonyl ships two macOS artifacts: the **`.pkg` installer** (inside a `.dmg`)
and the **raw runtime tarball** `carbonyl-<version>-aarch64-apple-darwin.tgz`.
Both are **self-signed but not notarized** — there's no Apple Developer ID
($99/year) behind these builds yet — so Gatekeeper warns on first launch.

> **Why the warning, and why it's safe.** macOS shows the "developer cannot be
> verified" / "Apple could not verify … is free of malware" dialog for *every*
> non-notarized app — the same wall Homebrew Cask apps and most open-source macOS
> binaries hit. It is not a malware finding. Verify the download against its
> published `.sha256` and detached GPG signature ([Verifying
> downloads](#verifying-downloads)) and you have the assurance notarization would
> give you. The native arm64 binary is **ad-hoc-signed** by the linker at build
> time and the tarball preserves that signature, so the only thing blocking it is
> the quarantine flag — not a missing code signature. It will not be killed on
> exec; it just needs the flag cleared.

### Option A — `.pkg` installer (in `.dmg`)

1. Open the `.dmg`, then double-click `carbonyl-<version>-macos-arm64.pkg`.
2. When macOS blocks it, either:
   - open **System Settings → Privacy & Security**, find the carbonyl message,
     click **Open Anyway**, and re-open the `.pkg`; or
   - clear the quarantine flag in Terminal first:
     ```bash
     xattr -dr com.apple.quarantine ~/Downloads/carbonyl-<version>-macos-arm64.pkg
     ```
3. The installer places the runtime in `/usr/local/carbonyl` and symlinks
   `/usr/local/bin/carbonyl`. Ensure `/usr/local/bin` is on your `PATH`.

### Option B — raw runtime tarball (no installer)

For users who'd rather not run an installer. The tarball unpacks to a
`aarch64-apple-darwin/` directory containing the `carbonyl` binary:

```bash
tar xzf carbonyl-<version>-aarch64-apple-darwin.tgz
# clear quarantine on the extracted runtime, then run it directly:
xattr -dr com.apple.quarantine aarch64-apple-darwin
./aarch64-apple-darwin/carbonyl https://example.com
```

If `-dr` leaves a stubborn flag, `xattr -cr aarch64-apple-darwin` (clear *all*
extended attributes) also works.

> **Re-quarantine on upgrade.** macOS re-applies `com.apple.quarantine` every
> time you re-download a build, so repeat the **Open Anyway** / `xattr` step
> after each upgrade — it's not a one-time-per-machine action.

A signed + notarized installer will replace the unsigned one once a Developer ID
is available (see [ADR-003](adr-003-native-install-packages.md), issue #129).

## Verifying downloads

Each artifact has a `.sha256` sidecar:

```bash
sha256sum -c carbonyl_<version>_amd64.deb.sha256
```

## Other distribution channels

- **npm:** `npm install -g carbonyl` (see the project readme).
- **Raw runtime tarball:** `carbonyl-<version>-<triple>.tgz` — unpack and run
  `./carbonyl`; used by the npm platform packages and for embedding.

For scriptable runtime acquisition from this repository, use semantic release
mode. It tries the public GitHub release first, falls back to the Gitea mirror,
verifies the `.sha256` sidecar before extraction, and runs `carbonyl --version`
when the downloaded binary is executable on the current host:

```bash
bash scripts/runtime-pull.sh --version <version> --dry-run
bash scripts/runtime-pull.sh --version <version>
```

Manual offline installs remain supported by unpacking a verified tarball yourself
or by pointing automation at an existing binary with `CARBONYL_BIN`.

## Architecture coverage

Native packages currently target **Linux x86_64** and **macOS arm64** (the arches
Carbonyl builds today). Linux arm64 packages follow once that runtime is built
(issue #116). Packaging internals: [packaging/README.md](../packaging/README.md)
and [ADR-003](adr-003-native-install-packages.md).
