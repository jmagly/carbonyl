# WORKSPACE.md
<!-- aiwg-managed -->
<!-- Generated structure by AIWG; operator content is protected by markers. -->

<!-- AIWG:workspace-context:start -->

## AIWG Context Graph

This file is the canonical provider-neutral home for project and operator context.
Provider startup files are generated adapters: they direct the harness here first,
then to AIWG.md for framework discovery and routing.

### Precedence

1. Provider, system, and organization instructions retain their native authority.
2. Root WORKSPACE.md supplies shared project/operator context.
3. AIWG.md supplies generated framework/discovery context.
4. Narrower linked files and provider-native subtree instructions govern their declared scope.

### Ownership

- Edit project-neutral notes only inside the protected Project Context section below.
- Keep detailed policies, runbooks, hooks, and quickrefs in linked files.
- Keep provider-only directives in `.aiwg/context/providers/`.
- Never store secrets, tokens, credentials, or machine-local sensitive values here.

### Linked Context

- [AIWG framework context](./AIWG.md)
- [AIWG project configuration](.aiwg/aiwg.config)
- [Project-local quickref](.aiwg/quickref.json) (when configured)

<!-- AIWG:workspace-context:end -->

<!-- AIWG:workspace-operator:start -->

## Project Context

### Commit signing

- Every repository commit MUST carry a valid OpenPGP signature made with Joseph Magly's commit-signing key, fingerprint `6229 7562 B1C7 0530 88F4 05DB 0117 DAAA 677A 5BF2`.
- Do not create or push an unsigned commit. If the required key or signing bridge is unavailable, stop before committing and report the blocker.
- Verify the effective signing configuration and the resulting commit signature as part of delivery. Do not substitute a bot, project release, or artifact-signing key.
- See [Commit and release signing](docs/SIGNING.md) for the key boundary and verification commands.

<!-- AIWG:workspace-operator:end -->
