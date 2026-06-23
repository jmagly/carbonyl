# Carbonyl release signing

Carbonyl release artifacts are GPG-signed with a **dedicated release key** (separate
from the maintainer's git-commit key). This file is the authoritative record of which
key signs releases — keep it current when the key rotates.

| Field | Value |
|-------|-------|
| Name  | Carbonyl Release Signing |
| Email | release@magly.net |
| Algorithm | ed25519 (sign) |
| Created | 2026-06-23 |
| Expires | 2031-06-22 |
| Fingerprint | `96B5 DCE9 275E 218C BAB9  CB28 2DE7 DD0D 3A89 96B50` |
| Key ID (long) | `2DE7DD0D3A8907C0` |

## Public key

- In this repo: [`keys/carbonyl-release.asc`](../keys/carbonyl-release.asc)
- Hosted for users: `https://magly.net/keys/carbonyl-release.asc` (roctinam/magly.net#32)

## How releases are signed (CI)

Every release artifact carries a **detached signature** `<artifact>.asc` plus per-asset
`<artifact>.sha256` and `<artifact>.md5`. Signatures are **per-asset** (not a single
manifest) because release assets arrive across multiple waves — the `release` job signs
the Linux/runtime tarballs and native packages, and the `package-macos` job signs the
macOS `.pkg`/`.dmg`. The **private key lives only as the CI secret
`CARBONYL_RELEASE_GPG_PRIVATE_KEY`** and is never committed. (roctinam/carbonyl#250)

MD5 is supplied for download-integrity / legacy-tooling compatibility only — it is
collision-broken and is **not** an authenticity guarantee. SHA-256 + the GPG signature
are the real integrity/authenticity controls.

## Verifying a release

```bash
# 1. import the key (from the site or this repo)
curl -fsSL https://magly.net/keys/carbonyl-release.asc | gpg --import
#    (or, from a repo checkout:  gpg --import keys/carbonyl-release.asc)

# 2. verify the artifact's detached signature
gpg --verify carbonyl-<ver>-<triple>.tgz.asc carbonyl-<ver>-<triple>.tgz
#    look for: Good signature from "Carbonyl Release Signing <release@magly.net>"

# 3. (optional) confirm integrity against the published checksum
sha256sum -c carbonyl-<ver>-<triple>.tgz.sha256
#    md5sum -c carbonyl-<ver>-<triple>.tgz.md5   # legacy/integrity only
```

## Rotation

Expires **2031-06-22**. Before expiry: generate a new key, publish the new public key
(repo + magly.net), update this doc and the CI secret, and keep the old public key
available so historical releases stay verifiable.
