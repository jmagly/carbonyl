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

The macOS installer is **unsigned** (no Apple Developer ID yet), so Gatekeeper
will warn on first launch. To install:

1. Open the `.dmg`, then double-click `carbonyl-<version>-macos-arm64.pkg`.
2. When macOS blocks it, either:
   - open **System Settings → Privacy & Security**, find the carbonyl message,
     click **Open Anyway**, and re-open the `.pkg`; or
   - clear the quarantine flag in Terminal first:
     ```bash
     xattr -d com.apple.quarantine ~/Downloads/carbonyl-*.pkg
     ```
3. The installer places the runtime in `/usr/local/carbonyl` and symlinks
   `/usr/local/bin/carbonyl`. Ensure `/usr/local/bin` is on your `PATH`.

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

## Architecture coverage

Native packages currently target **Linux x86_64** and **macOS arm64** (the arches
Carbonyl builds today). Linux arm64 packages follow once that runtime is built
(issue #116). Packaging internals: [packaging/README.md](../packaging/README.md)
and [ADR-003](adr-003-native-install-packages.md).
