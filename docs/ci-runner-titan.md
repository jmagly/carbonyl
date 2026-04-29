# Titan CI Runner — Host State Runbook

**Closes (in part)**: `#55`
**Referenced by**: `#49`, `#51`, `#57`, `#60` (Phase 0 tracker)
**Related**: `docs/ci-cd-plan.md` for the architectural picture

## Scope

Titan is Carbonyl's designated build host. Chromium builds run on titan exclusively (only machine with enough cores / RAM / disk for the 150 GB source + 40 GB build artifacts + multi-hour rebuilds). This document captures what titan needs to be in, how to set it up, and how to recover from drift.

## One-time bootstrap

Required the first time titan is used for Carbonyl, and any time a fresh titan is provisioned. Idempotent — safe to re-run.

### 1. Docker daemon

Installed via distro package. Verify:

```bash
docker info | head -5
# should show: Server Version: 29.4.0 (or similar)
```

### 2. Gitea runner service

Installed and registered for the `roctinam/carbonyl` repo (+ any other repos that use titan). Labels must include `titan` so `runs-on: titan` workflows land here.

```bash
systemctl status gitea-runner
# labels check: /etc/gitea-runner/config.yaml
```

### 3. Chromium source checkout — the big one

Chromium source lives at **`/srv/carbonyl/`** on titan. This path is referenced by `.gitea/workflows/build-runtime.yml` as `HOST_CARBONYL_DIR`. The expected layout:

```
/srv/carbonyl/
├── chromium/
│   ├── src/             ← ~150 GB Chromium checkout (the heavy one)
│   ├── depot_tools/     ← Google's build tooling (git submodule in the repo)
│   └── patches/         ← Carbonyl patches
├── src/                 ← Carbonyl Rust crate + bridge + browser/args.gn
├── scripts/             ← build.sh, patches.sh, gn.sh, env.sh ...
├── build/               ← pre-built artifacts accumulate here
│   ├── Dockerfile.builder
│   └── pre-built/       ← runtime tarballs before upload
└── ... (rest of the roctinam/carbonyl repo tree)
```

The `chromium/src/` directory is persistent across builds. Each workflow run syncs the non-Chromium files from the workspace checkout into `/srv/carbonyl/` via rsync, preserving the heavy checkout. See `.gitea/workflows/build-runtime.yml` step "Sync workspace → host Chromium checkout".

#### Bootstrap option A — rsync from a host that already has the source (fastest on LAN)

Assuming grissom has `/srv/vmshare/dev-inbox/carbonyl/carbonyl/` ready:

```bash
# On grissom, with an ssh key to titan:
rsync -av --info=progress2 \
  --exclude='chromium/src/out/' \
  --exclude='target/' \
  --exclude='**/target/' \
  --exclude='node_modules/' \
  --exclude='.venv*/' \
  --exclude='__pycache__/' \
  /srv/vmshare/dev-inbox/carbonyl/carbonyl/ \
  titan:/srv/carbonyl/
```

Take note: `/srv/carbonyl/` needs to be writable by the user the rsync is authenticating as. If the mount point needs root, rsync with `sudo` on titan via `--rsync-path="sudo rsync"`.

#### Bootstrap option B — fresh `gclient sync` (falls back when no rsync source)

```bash
# On titan:
sudo mkdir -p /srv/carbonyl && sudo chown $USER /srv/carbonyl
git clone https://git.integrolabs.net/roctinam/carbonyl.git /srv/carbonyl
cd /srv/carbonyl
git submodule update --init --recursive   # fetches chromium/depot_tools
bash scripts/gclient.sh sync              # ~150 GB pull from Google; expect hours
bash scripts/patches.sh apply
```

Option A is preferred when available (LAN-speed; one pass).

### 4. Verify the bootstrap

```bash
# On titan:
du -sh /srv/carbonyl/chromium/src   # expect ~150 GB
ls /srv/carbonyl/chromium/depot_tools/ | head   # expect autoninja, gclient, gn, etc.
cd /srv/carbonyl && git log --oneline -3   # should show recent carbonyl commits
```

### 5. Gitea registry login (for workflows that pull the builder image)

```bash
# On titan, as the user the runner runs as:
echo "$BUILD_REPO_TOKEN" | docker login git.integrolabs.net -u <actor> --password-stdin
```

The token is the same one referenced by `secrets.BUILD_REPO_TOKEN` in workflows.

## Ongoing maintenance

### Bumping the pinned builder image

The consumer workflows (`check.yml`, `build-runtime.yml`, `release.yml`) all read the carbonyl-builder image tag from `.gitea/builder-image-pin` at the repo root. The pin is a single line containing a tag like `sha-7458695` and is the canonical version every CI job uses.

When `Dockerfile.builder` changes:

1. Land the `Dockerfile.builder` change. `build-builder.yml` fires and publishes a new image tagged `sha-<new-7-char-sha>` (and refreshes `:latest`).
2. Wait for the `build-builder.yml` run to go green.
3. Update `.gitea/builder-image-pin` to the new tag in a follow-up commit (or in the same PR, after the green CI).
4. Subsequent `check.yml` / `build-runtime.yml` / `release.yml` runs pick up the new image. The fallback is `:latest` if the pin file goes missing.

To run a one-off workflow against a different image without touching the pin file:

```
workflow_dispatch → builder_image_tag = sha-<other> (or "latest")
```

Each consumer workflow exposes that input.

### Chromium source stays current automatically

Workflows rsync the workspace checkout onto `/srv/carbonyl/` for every build, so Carbonyl's own sources update per-run. The `chromium/src/` tree stays at whatever version matches the patches' target upstream commit. When Carbonyl bumps Chromium versions (see `docs/chromium-upgrade-plan.md`), the first post-bump build will `gclient sync` internally. Titan itself doesn't need manual intervention.

### Cache sizing

- `chromium/src/` grows slowly over time (Chromium adds files). Budget 200 GB.
- `out/Default-*/` build outputs: up to 40 GB per variant. With `headless`, `x11`, and potentially `both` variants active, budget 120 GB.
- Docker layer storage for the builder image: under 2 GB.
- Total working budget for Carbonyl on titan: ~500 GB. Titan has 5.2 TB free; comfortable margin.

### Periodic cleanup

Safe to prune:

```bash
# Old build outputs for ozone variants no longer in use
rm -rf /srv/carbonyl/chromium/src/out/Default-<old-variant>

# Old runtime tarballs (they're uploaded to Gitea releases; local copies are redundant)
find /srv/carbonyl/build/pre-built -name '*.tgz' -mtime +14 -delete

# Docker image cleanup (keep the 5 most recent builder images)
docker images git.integrolabs.net/roctinam/carbonyl-builder --format '{{.Tag}} {{.ID}}' | \
  grep '^sha-' | tail -n +6 | awk '{print $2}' | xargs -r docker rmi
```

Unsafe to prune:

- `/srv/carbonyl/chromium/src/` — source tree; re-fetching is hours
- `/srv/carbonyl/chromium/depot_tools/` — git submodule; restorable but slows recovery
- Anything else under `/srv/carbonyl/` without knowing what it's for

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Workflow step "Sync workspace → host Chromium checkout" fails with `/srv/chromium/src missing` | Bootstrap never ran | Run the bootstrap steps above |
| `ninja` errors about missing `//out/Default/args.gn` | gn gen step didn't run or was deleted | Re-trigger workflow with `builder_image_tag=<known-good>` |
| Build runs out of disk | `out/` outputs piled up | `df -h /srv/carbonyl`; prune per above |
| Docker pull fails with 401 | Registry login expired | Re-run step 5 of bootstrap |
| `docker login` fails | `BUILD_REPO_TOKEN` expired | Rotate in Gitea secrets; re-run runner steps |
| Chromium source shows local modifications (`git status` non-empty) | Patches not cleaned between builds | `cd /srv/carbonyl/chromium/src && git reset --hard && git clean -xfd`; re-apply via `scripts/patches.sh apply` |
| Slow build (not half-cores respected) | `NINJA_JOBS` override missing or wrong | Set `ninja_jobs` workflow_dispatch input explicitly |

## Parameterized build

Per `#57`, `.gitea/workflows/build-runtime.yml` exposes three workflow_dispatch inputs:

| Input | Options | Default | Effect |
|-------|---------|---------|--------|
| `arch` | `amd64`, `arm64` | `amd64` | Target architecture; picks up via `platform-triple.sh` |
| `ozone_platform` | `headless`, `x11`, `both` | `headless` | In-workflow `sed` on `args.gn`; original restored after build (even on failure, via `if: always()`) |
| `builder_image_tag` | any tag | `latest` | Pins the `carbonyl-builder` image the build runs inside |
| `ninja_jobs` | integer | `nproc / 2` | ninja `-j` parallelism |

The `ozone_platform=x11` path is what Phase 0 W0.2 (`#57`) needs. The `ozone_platform=both` path supports `#62` (W0.6 text-render parity).

## Trigger a test build manually

```bash
# Via Gitea UI:
#   Actions → Build Runtime → workflow_dispatch →
#     arch=amd64, ozone_platform=x11, ninja_jobs=16

# Via API (scripted):
curl -X POST \
  -H "Authorization: token ${GITEA_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://git.integrolabs.net/api/v1/repos/roctinam/carbonyl/actions/workflows/build-runtime.yml/dispatches" \
  -d '{"ref": "main", "inputs": {"arch": "amd64", "ozone_platform": "x11", "ninja_jobs": "16"}}'
```

## Disaster recovery

If titan itself is reprovisioned, repeat the full bootstrap. No titan-local state is authoritative — the Chromium checkout on grissom (or a fresh `gclient sync`) is the recovery source. Runtime tarballs live in Gitea releases, not on titan.

## See also

- `docs/ci-cd-plan.md` — architecture + planned workflow set
- `.gitea/workflows/build-builder.yml` — `#49`, builder image publish
- `.gitea/workflows/build-runtime.yml` — `#51` + `#57`, runtime build inside container with ozone parameterization
- `docs/chromium-upgrade-plan.md` — how Chromium version bumps happen
- `.aiwg/working/trusted-automation/09-ci-plan.md` — initiative-specific CI
- Fortemi runner pattern: `Fortemi/fortemi` `.gitea/workflows/build-builder.yaml` — reference implementation this mirrors
