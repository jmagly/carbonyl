# CI Secrets and Token Rotation

Operational reference for every secret the Carbonyl CI pipeline depends
on. Audit artifact for compliance; runbook for rotation; recovery
procedure if a token is believed leaked.

This doc is **authoritative**: if a workflow YAML references a
`secrets.X` not listed in the table below, that's a drift bug — file
a PR to either remove the reference or document the new secret here.

---

## Secret inventory

| Secret | Identity | Type | Scope (minimum) | Used by | Rotation |
|---|---|---|---|---|---|
| `BUILD_REPO_TOKEN` | bot account `roctibot` on `git.integrolabs.net` | Gitea PAT | `write:package`, `write:release`, `read:package` on `roctinam/carbonyl` | `build-builder.yml`, `build-runtime.yml`, `check.yml`, `release.yml` (#52), `publish-image.yml` (#132) | 90 days |
| `GH_MIRROR_TOKEN` | bot account `jmagly-mirror` on `github.com` | GitHub fine-grained PAT | `contents: write`, `metadata: read` on `jmagly/carbonyl` only | `mirror.yml` (#53), `release.yml` mirror step (#52) | 90 days |
| `GHCR_TOKEN` | user `jmagly` on `github.com` | GitHub classic PAT | `write:packages`, `read:packages` on the `ghcr.io/jmagly` namespace | `publish-image.yml` (#132) | 90 days |
| `RUNTIME_PUBLISH_TOKEN` | **user `roctinam`** on `git.integrolabs.net` (human, not a bot — see note) | Gitea PAT | `write:release`, `read:package` on `roctinam/carbonyl` | `build-runtime-arm64.yml` (#116) — publish step only | 90 days |

> **`RUNTIME_PUBLISH_TOKEN` — status: NOT YET PROVISIONED (2026-06-15).** Until it
> is created and added as a repo Actions secret, `build-runtime-arm64.yml` with
> `publish=true` fails loudly by design; `publish=false` and `preflight_only=true`
> need no token and work today.
>
> This token is intentionally a **`roctinam` human PAT**, an exception to the
> "Bot identity, not human" scope principle below, for two reasons: (1) the mutsu
> driver (`scripts/mutsu-build-linux-arm64.sh`) does `docker login -u roctinam`
> and `runtime-push.sh` uploads the release asset as the token's user — a bot
> token would fail the login and mis-attribute the asset; (2) the delivery-identity
> policy requires all deliveries (commits, tags, release assets, tracker writes) to
> be attributed to the GPG-signed configured user `roctinam`, never the `roctibot`
> bot. Do **not** substitute `BUILD_REPO_TOKEN` (that one is `roctibot`).
> Reconciling the broader "bot identity" principle with the delivery-identity
> policy is tracked upstream in `roctinam/aiwg#1601` (config-schema support for a
> declared committer + signing + forge tracker-actor).

`github.actor` (auto-injected by Gitea Actions) is the username used
for `docker login` against the Gitea registry. It is not a secret —
the auth comes from `BUILD_REPO_TOKEN` paired with the actor name. No
separate `GITEA_REGISTRY_USER` secret is needed.

`GHCR_TOKEN` is deliberately a **`jmagly` user** PAT, not the
`jmagly-mirror` bot: `ghcr.io/jmagly` is a *user* namespace, and only
the namespace owner's token can create/push packages there. ghcr push
needs `write:packages`, which a classic PAT grants reliably (fine-grained
PAT support for GHCR is still limited). The `publish-image.yml` login user
is the literal `jmagly` (workflow env `GHCR_USER`), not `github.actor`.
First push creates a **private** package — make it public at
`https://github.com/users/jmagly/packages` for anonymous `docker pull`.

## Scope principles

- **Minimum scope per token.** Each PAT is scoped to exactly the
  resources its consuming workflows touch. `BUILD_REPO_TOKEN` is
  repo-scoped to `roctinam/carbonyl`, not user-wide. `GH_MIRROR_TOKEN`
  is repo-scoped to `jmagly/carbonyl` via GitHub fine-grained PAT,
  not classic-PAT user-wide.
- **No "just in case" scopes.** Adding a scope because a future
  workflow might need it creates exposure for no current benefit. Add
  the scope when the workflow lands, not before.
- **Bot identity, not human.** Tokens are issued from dedicated bot
  accounts (`roctibot` on Gitea, `jmagly-mirror` on GitHub) so they
  can be rotated/revoked without disrupting an admin's personal
  workflow.
- **One token, one purpose.** No reuse across more workflows than
  what's listed in the inventory column. If a new workflow needs the
  same scope, it can share the token; if it needs a different scope,
  it gets a new token.

## Rotation procedure

Rotate every 90 days. Set a calendar reminder per token.

1. **Generate new PAT** in the relevant identity's settings.
   - Gitea: `https://git.integrolabs.net/user/settings/applications`
     → "Generate New Token" with the scopes from the inventory table.
     Set expiry to ~95 days (5-day grace).
   - GitHub: `https://github.com/settings/personal-access-tokens/new`
     → fine-grained, 90-day expiry, repo: `jmagly/carbonyl`,
     permissions per inventory row.
2. **Update Gitea repo secret**.
   `https://git.integrolabs.net/roctinam/carbonyl/settings/actions/secrets`
   → click the existing secret name → paste new value → save. (Gitea
   stores by name; this overwrites the prior value without exposing it.)
3. **Verify each consumer**. For each workflow listed in the inventory:
   - `workflow_dispatch` it (or wait for the next push trigger)
   - confirm the run reaches the step that authenticates with the
     token (e.g. `docker login`, `curl … -H Authorization`)
4. **Revoke the old PAT** once all consumers report green. Don't
   revoke before — it's the only way to be sure nothing was caching
   the previous value.

## Provisioning a new secret

When adding a workflow that needs a new identity-scoped credential:

1. Add a row to the inventory table in this doc **first**, in the same
   PR as the workflow YAML.
2. Provision the bot account if one doesn't exist for that identity
   (don't issue tokens from human admins).
3. Generate the PAT with the documented scope.
4. Add it to Gitea repo secrets under the documented name.
5. Land the PR. The reviewer's job includes confirming this doc was
   updated.

## Leak response playbook

A secret is "believed leaked" the moment any of:
- the value appears in a public log, a public commit, or a public chat
- a workflow run produces an unexpected change attributable to the token
- the bot account shows sign-in activity from an unrecognised location
- a developer pasted the value into a non-secret field and remembers
  doing it

Within minutes:

1. **Revoke the leaked PAT** at its origin (Gitea or GitHub). Do not
   wait for cleanup. Revoke first, investigate after.
2. **Rotate**: generate a fresh PAT and update the repo secret per the
   rotation procedure above. Workflows will fail until step 3.
3. **Confirm the secret name in Gitea is updated** before rerunning
   any workflow that consumed it.

Within hours:

4. **Audit blast radius**:
   - Gitea: review repo audit log for actions taken with that token
     since its issue date. Look for unexpected releases, package
     uploads, force-pushes.
   - GitHub: review `jmagly/carbonyl` release/tag history and the
     `jmagly-mirror` account's activity log.
5. **Scrub the public surface**: if the leak was via commit or log,
   verify the value is removed (force-push, log redaction, etc.).
   Even after revocation, leaked tokens should not remain visible —
   they're an attack-pattern artifact.
6. **Document**: short post-incident note in `docs/incidents/` (create
   the dir if not present) capturing: what leaked, when, blast radius
   findings, what was changed to prevent recurrence.

## mutsu SSH access (not a Gitea secret)

The arm64 Linux runtime build (`build-runtime-arm64.yml`, #116) and the macOS
arm64 runtime build are **SSH-dispatched to mutsu** from the `titan` runner —
mutsu cannot host a Gitea Actions runner (macOS `act_runner` RPC limitation; see
`docs/ci-runner-mutsu.md`). The SSH credential for mutsu is therefore **not a
Gitea Actions secret**: it lives on the runner host's filesystem in the runner
user's `~/.ssh`, and the job inherits it because `act_runner` runs the job as
that host user.

Required on the `titan` runner host (provisioned operationally, out of band):

| Item | Value | Notes |
|---|---|---|
| Private key | `~/.ssh/agentic_ed25519` (or as referenced by the host config) | ed25519; the key authorized on `mutsu` for the build user |
| SSH config entry | `Host mutsu-agent` → `HostName 10.0.42.41`, `User manitcor`, `IdentityFile ~/.ssh/agentic_ed25519` | `build-runtime-arm64.yml` passes `--ssh-config "$HOME/.ssh/config"`; override with the workflow's `ssh_config` input if it lives elsewhere |
| Host key | in the runner user's `known_hosts` | the driver uses `ssh -o BatchMode=yes`; the host key must already be trusted (no interactive prompt) |

This is intentionally **runner-host material, not a rot-managed Gitea secret** —
it cannot be injected per-run because the build is a long-lived SSH session, and
it is shared with the macOS arm64 build. If the runner host is rebuilt or the
mutsu key rotates, re-provision `~/.ssh` on the runner. The workflow's
`preflight_only=true` mode verifies reachability without starting a build.

## Out of scope

- **Automated rotation** via an external vault (HashiCorp Vault, etc.).
  Manual 90-day rotation is acceptable at current scale; revisit when
  we have >5 active tokens or a compliance trigger.
- **Signing / attestation secrets** (cosign, sigstore). Defer until
  release signing is in scope.
- **Per-environment secrets** (staging vs. production). Carbonyl
  has one CI environment.

## References

- Gitea Actions secrets UI:
  `https://git.integrolabs.net/roctinam/carbonyl/settings/actions/secrets`
- GitHub fine-grained PATs:
  `https://github.com/settings/personal-access-tokens`
- Parent CI plan: `docs/ci-cd-plan.md`
- Mirror workflow: `#53`, release workflow: `#52`
