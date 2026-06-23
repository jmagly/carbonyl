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

`release.yml` signs the checksums manifest (`SHA256SUMS` / `MD5SUMS`) — and/or
per-asset `.asc` — with this key. The **private key lives only as the CI secret
`CARBONYL_RELEASE_GPG_PRIVATE_KEY`** and is never committed. Signing implementation
is tracked in roctinam/carbonyl#250.

## Verifying a release

```bash
# import the key (from the site or this repo)
curl -fsSL https://magly.net/keys/carbonyl-release.asc | gpg --import
# verify the signed checksums, then check the asset
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```

## Rotation

Expires **2031-06-22**. Before expiry: generate a new key, publish the new public key
(repo + magly.net), update this doc and the CI secret, and keep the old public key
available so historical releases stay verifiable.
