# Risk Screening — Carbonyl Automation Layer

**Document Type**: Risk Register (Initial Screening)
**Generated**: 2026-04-02
**Author**: Security Architect
**Scope**: Carbonyl Automation Layer (Python library wrapping Carbonyl terminal browser)
**Components**: CarbonylBrowser, DaemonClient, SessionManager, ScreenInspector

---

## Summary

This risk screening covers the Carbonyl Automation Layer, a Python library that automates web interactions through the Carbonyl terminal browser (headless Chromium). The automation layer introduces several security-sensitive design choices — plaintext credential storage, unauthenticated daemon sockets, sandbox-disabled execution, and bot-detection evasion techniques — that carry material risk in both security and legal dimensions.

**Risk Profile**: Elevated. Three risks are rated Critical or High severity. The combination of plaintext credentials, world-readable MFA delivery, and an unauthenticated daemon socket creates a local privilege escalation chain: any process on the host can connect to the daemon, trigger authenticated sessions, and exfiltrate stored credentials or session tokens.

**Key Findings**:

- 3 risks rated **High** or **Critical** severity (R-001, R-003, R-005)
- 4 risks rated **Medium** severity (R-002, R-004, R-006, R-008)
- 3 risks rated **Low** severity (R-007, R-009, R-010)
- 0 risks currently **Mitigated**; all are **Open** or **Accepted**

**Recommendation**: Address R-001, R-003, and R-005 before any deployment beyond single-user development workstations. R-004 (ToS/legal) requires a policy decision from stakeholders before expanding scope.

---

## Risk Register

| ID | Category | Description | Likelihood | Impact | Severity | Mitigation | Status |
|----|----------|-------------|------------|--------|----------|------------|--------|
| R-001 | Security | **Plaintext credential storage.** USPS credentials stored in `~/.config/usps/credentials` as plaintext with mode 600. Any process running as the same user, or any root-level compromise, exposes these credentials directly. No encryption at rest. | High | High | **Critical** | Encrypt credentials using OS keyring (e.g., `keyring` library or `libsecret`). At minimum, use a symmetric key derived from a user-provided passphrase. Remove plaintext fallback once migration is complete. | Open |
| R-002 | Security | **Incomplete bot-detection evasion.** Firefox UA spoofing and `--disable-http2` partially mask the browser identity, but the JA3/JA4 TLS fingerprint remains identifiably Chromium. Sophisticated server-side fingerprinting (Akamai, Cloudflare, PerimeterX) can still detect and block automated access, potentially triggering account lockouts or IP bans. | High | Med | **High** | Accept as known limitation. Document which target sites perform JA3 fingerprinting. Consider TLS fingerprint randomization libraries (e.g., `curl-impersonate` integration) if blocking becomes operational. Monitor for account lockout events. | Accepted |
| R-003 | Security | **MFA code delivered via world-writable path.** MFA codes are passed through `/tmp/usps_mfa_code`. The `/tmp` directory is world-writable, meaning any local user or process can read, overwrite, or race the MFA code. This enables MFA bypass via code injection or interception. | High | High | **Critical** | Move MFA file to a user-private directory (e.g., `~/.config/usps/mfa_code`) with mode 600. Alternatively, use a named pipe or Unix socket for ephemeral delivery. Delete the file immediately after consumption. | Open |
| R-004 | Legal/ToS | **Automated access to USPS may violate Terms of Service.** USPS.com Terms of Service may prohibit automated access, scraping, or bot-driven interactions. Violation could result in account suspension, IP blocking, or legal action. Similar risk applies to any other site accessed through the automation layer. | Med | High | **High** | Obtain legal review of USPS ToS and any other target site policies. Document acceptable use boundaries. Implement rate limiting and human-like interaction delays. Consider whether USPS provides an official API for the required functionality. | Open |
| R-005 | Security | **Unauthenticated daemon socket.** The DaemonClient exposes a Unix socket with no authentication. Any local process can connect and issue commands to the browser, including navigating to authenticated sessions, extracting page content, or injecting keystrokes. Combined with R-001 and R-006, this creates a local attack chain. | Med | High | **High** | Add socket-level authentication (shared secret or token file with restricted permissions). Set socket file permissions to mode 600 and verify ownership on connection. Consider `SO_PEERCRED` to validate connecting process UID. | Open |
| R-006 | Security | **Unencrypted session profile persistence.** Chromium user-data-dir stores cookies, session tokens, local storage, and cached credentials on disk without encryption. Any file-level access to the profile directory exposes all stored authentication state. | Med | Med | **Medium** | Restrict profile directory permissions to mode 700. Consider encrypted filesystem overlay (e.g., `fscrypt`, `ecryptfs`) for profile storage. Implement session expiry and profile cleanup on daemon shutdown. Document the threat in operator runbook. | Open |
| R-007 | Reliability | **Daemon crash leaves orphan Chromium processes.** If the daemon process terminates unexpectedly (OOM, signal, crash), spawned Chromium processes may continue running as orphans, consuming resources and holding file locks on the profile directory. Restarting the daemon may fail due to locked profile or stale socket file. | Med | Low | **Low** | Implement PID tracking and cleanup on daemon startup. Use a PID file or process group to enable reliable teardown. Add a health-check endpoint to the daemon socket. Handle stale socket file removal on startup. | Open |
| R-008 | Dependency | **Upstream Carbonyl abandonment risk.** Carbonyl upstream is at v0.0.3 with the last commit in 2023. The embedded Chromium version is frozen at whatever was bundled at that release, meaning known CVEs in that Chromium version will not receive patches. No upstream security response process exists. | High | Med | **Medium** | Maintain a fork with the ability to update the embedded Chromium version independently. Track Chromium CVEs against the bundled version. Document the exact Chromium version in use and its known vulnerabilities. Establish criteria for when a Chromium update is mandatory (e.g., any actively exploited CVE in the rendering or networking stack). | Open |
| R-009 | Reliability | **Session expiry and MFA timeout.** Automated sessions depend on cookie persistence and may expire unpredictably. MFA challenges have time-limited windows; if the automation cannot deliver and consume the MFA code within that window, the login flow fails and may trigger account security alerts or lockouts. | Med | Low | **Low** | Implement session health checks before critical operations. Add retry logic with exponential backoff for MFA flows. Monitor session expiry patterns and refresh proactively. Alert on repeated MFA failures as a potential lockout indicator. | Open |
| R-010 | Operational | **Profile disk usage growth.** Chromium user-data-dir profiles accumulate cache, local storage, and history data over time. Without cleanup, profile directories can grow to multiple gigabytes per session, especially with media-heavy sites. | Low | Low | **Low** | Implement periodic cache clearing within profiles. Set Chromium flags to limit cache size (`--disk-cache-size`). Add profile size monitoring and alerting. Consider ephemeral profiles for non-session-critical operations. | Open |
| R-011 | Security | **Chromium sandbox disabled.** Using `--no-sandbox` removes Chromium's process-level sandboxing, meaning a renderer exploit can directly compromise the host process and potentially the system. While common in Docker environments, it significantly increases the blast radius of any Chromium vulnerability. | Med | High | **High** | Run Carbonyl inside a container with its own security boundary (seccomp, AppArmor/SELinux profile) when `--no-sandbox` is required. Never run `--no-sandbox` on a multi-user host outside a container. Document which deployment contexts require sandbox disabling and enforce container-only operation for those cases. | Open |

---

## Severity Matrix

|            | **Low Impact** | **Medium Impact** | **High Impact** |
|------------|:--------------:|:-----------------:|:---------------:|
| **High Likelihood**   | Low | **Medium** (R-002) | **Critical** (R-001, R-003) |
| **Medium Likelihood** | **Low** (R-007) | **Medium** (R-006, R-008) | **High** (R-004, R-005, R-011) |
| **Low Likelihood**    | **Low** (R-009, R-010) | Low | Medium |

---

## Next Steps

1. **Immediate** (before any non-dev deployment): Address R-001 (credential encryption), R-003 (MFA file path), and R-005 (socket authentication).
2. **Short-term**: Obtain legal/ToS review for R-004. Implement R-011 mitigations (container-only sandbox-disabled execution).
3. **Ongoing**: Track upstream Chromium CVEs against bundled version (R-008). Monitor for bot-detection escalation (R-002).
4. **Accept or defer**: R-007, R-009, R-010 are low severity and can be addressed as operational improvements over time.

---

## Revision History

| Date | Author | Change |
|------|--------|--------|
| 2026-04-02 | Security Architect | Initial risk screening |
