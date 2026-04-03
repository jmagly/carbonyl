# Security Review — Carbonyl Automation Layer SAD

**Reviewer**: Security Architect
**Date**: 2026-04-02
**Document Reviewed**: software-architecture-doc.md v1.0
**Verdict**: CONDITIONAL

## Summary

The SAD accurately describes the system's architecture but treats security as a description of existing behavior rather than a set of controls to be enforced. Section 8 acknowledges the `--no-sandbox` flag and default socket permissions, but does not prescribe mitigations, leaving three Critical/High risks from the risk register (R-001, R-003, R-005) unaddressed at the architectural level. The SAD cannot be baselined until it incorporates explicit security controls for credential handling, daemon authentication, and sandbox-disabled execution boundaries.

## Findings

### Critical

**F-01: SAD Section 8.2 documents R-001/R-005/R-011 as facts, not as risks with controls.**
Section 8.2 states "No credentials are stored by the automation layer itself" and "the Unix socket has default file permissions (no explicit ACL)." These are accurate descriptions but the SAD should define target-state controls, not merely record current gaps. The risk register rates R-001 and R-005 as Critical and High respectively; the SAD's silence on mitigations makes it appear these are accepted by design.

**F-02: R-003 (MFA via /tmp) is entirely absent from the SAD.**
The SAD does not mention the MFA code delivery mechanism at all. A world-writable `/tmp` path for MFA codes is a Critical risk and represents a direct authentication bypass vector. This must be documented in Section 8 with a prescribed alternative (user-private directory or ephemeral pipe).

### High

**F-03: No threat model for the daemon's attack surface.**
The daemon accepts arbitrary JSON commands over an unauthenticated Unix socket (Section 5.2). The SAD does not model what an attacker with local socket access can do: navigate to authenticated sites, exfiltrate page content, inject keystrokes, or trigger credential entry. This is the core of R-005 and needs explicit architectural treatment -- at minimum, socket permission enforcement (mode 0600) and `SO_PEERCRED` UID validation.

**F-04: Frozen Chromium version + no-sandbox = compounding risk.**
Section 8.2 notes `--no-sandbox` and Section 11 notes the abandoned upstream, but these are presented in isolation. Combined, they mean any Chromium RCE in the frozen version has no sandbox to contain it. The SAD should mandate a compensating container boundary when `--no-sandbox` is active (the mitigation proposed for R-011) and document the bundled Chromium version explicitly.

### Medium / Low

**F-05: ThreadingUnixStreamServer without synchronization (Section 10.3).**
The SAD correctly identifies this gap but classifies it as a concurrency concern. It is also a security concern: a malicious local process could race legitimate commands to corrupt browser state or extract content from an authenticated page mid-operation.

**F-06: Session profile permissions not specified.**
Section 5.3 describes the session storage layout but does not prescribe directory permissions. The Chromium profile contains cookies, localStorage, and cached credentials (risk R-006). The SAD should require mode 0700 on profile directories and mode 0600 on `session.json`.

**F-07: Docker fallback volume mount exposes profile.**
Section 9.2 notes that Docker mode mounts the session profile as a volume. If the Docker image is untrusted or shared, the profile contents (including authentication state) are exposed to the container. The SAD should note this trust boundary.

## Recommendations

1. **Add a Security Controls subsection to Section 8** that prescribes target-state mitigations for R-001, R-003, R-005, and R-011, rather than describing current (insecure) behavior as the architecture.
2. **Document the MFA delivery mechanism** in Section 8 and mandate a user-private path with mode 0600, replacing `/tmp`.
3. **Add daemon socket authentication** to the Section 5.2 design: enforce socket file mode 0600 at creation, validate peer UID via `SO_PEERCRED`, and document this as a security invariant.
4. **Mandate a container boundary** for `--no-sandbox` execution in Section 9, with a minimum seccomp profile. Document the exact bundled Chromium version and its CVE exposure.
5. **Specify file permissions** for session directories (0700) and metadata files (0600) in Section 5.3.
6. **Add a command-level lock** to the daemon design (Section 5.2) to prevent concurrent command interleaving, addressing both the reliability and security dimensions.
7. **Document the Docker volume trust boundary** in Section 9.2, noting that mounting a profile into an untrusted container exposes all session authentication state.

## SAD Sections Needing Revision

- **Section 5.2** (Daemon): Add socket permission enforcement, `SO_PEERCRED` validation, and command serialization.
- **Section 5.3** (SessionManager): Specify directory and file permission requirements.
- **Section 8** (Security Architecture): Add a controls/mitigations subsection covering R-001, R-003, R-005, R-011. Document MFA delivery. Record bundled Chromium version.
- **Section 9.2** (Binary Resolution): Add trust boundary note for Docker profile volume mounts.
- **Section 11** (Known Gaps): Cross-reference the risk register IDs for traceability.
