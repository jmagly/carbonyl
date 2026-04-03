# Synthesis Report: Software Architecture Document -- Carbonyl Automation Layer

**Date:** 2026-04-03
**Synthesizer:** Documentation Synthesizer
**Document Version:** 1.1

## Contributors

**Primary Author:** architecture-documenter
**Reviewers:**
- Security Architect (CONDITIONAL): Identified missing security controls, MFA threat surface, daemon socket threat model, file permission gaps
- Test Architect (CONDITIONAL): Identified PTY testability gap, daemon reconnect coverage, dispatch symmetry enforcement, bot-bypass limitation
- Requirements Analyst (APPROVED_WITH_SUGGESTIONS): Validated use case and NFR traceability, identified Python version discrepancy, flagged unresolved architectural decisions in gap table

## Feedback Summary

### Additions (New Content)
- Section 8.2 (permission table): Added by Security Architect + Requirements Analyst -- explicit file permission specs for socket, profile directory, session.json, MFA code files
- Section 8.2 (MFA bullet): Added by Security Architect -- R-003 MFA /tmp threat surface documented
- Section 8.3 (Security Controls): Added by Security Architect -- prescriptive mitigations for R-001, R-003, R-005, R-011
- Section 8.4 (Daemon Socket Threat Model): Added by Security Architect -- enumerated attack vectors for unauthenticated socket access
- Section 10.5 (Testability): Added by Test Architect -- PTY injection seam, daemon reconnect scenario, dispatch symmetry constraint, bot-bypass accepted limitation
- Section 11 (disconnect flush): Added by Requirements Analyst -- architectural decision resolving UC-004 / OQ-002

### Modifications (Changes)
- Section 1 (Document Control): Updated version to 1.1, status to BASELINED, date to 2026-04-03
- Section 9.1 (Runtime Prerequisites): Changed "Python 3.10+" to "Python 3.11+" per Requirements Analyst (NFR-011 alignment)
- Section 11 (daemon logs): Converted passive gap description to actionable architectural decision with target path and iteration assignment, per Requirements Analyst

### Validations (Approvals)
- Requirements Analyst: APPROVED_WITH_SUGGESTIONS -- all 5 use cases traced, 10/14 NFRs fully covered
- Security Architect: CONDITIONAL -- conditions addressed by adding Sections 8.3 and 8.4
- Test Architect: CONDITIONAL -- conditions addressed by adding Section 10.5

## Conflicts Resolved

No conflicts between reviewers. All three reviews were complementary: security focused on controls, testability on verification seams, and traceability on consistency and completeness. No reviewer contradicted another.

## Changes Made

**Structural:**
- Added Section 8.3 (Security Controls) with four risk mitigations
- Added Section 8.4 (Daemon Socket Threat Model)
- Added Section 10.5 (Testability) with four subsections
- Added permission requirements table to Section 8.2
- Added MFA bullet to Section 8.2
- Added two new entries to Section 11 gap table

**Content:**
- Fixed Python version from 3.10+ to 3.11+ in Section 9.1
- Converted NFR-014 gap entry from passive description to actionable architectural decision
- Converted disconnect flush gap from implicit to explicit architectural decision

**Quality:**
- Updated all metadata (frontmatter, document control table, revision history) to reflect v1.1 BASELINED status

## Outstanding Items

**Requires Follow-up:**
1. Implement `os.chmod(socket_path, 0o600)` in `_BrowserServer` -- Owner: developer -- Due: construction iteration 1
2. Implement `os.makedirs(profile_path, mode=0o700)` in `SessionManager.create()` -- Owner: developer -- Due: construction iteration 1
3. Add `SO_PEERCRED` UID validation to `_BrowserHandler` -- Owner: developer -- Due: construction iteration 1
4. Introduce PTY injection seam (pre-populated `pyte.Screen` constructor) -- Owner: developer -- Due: construction iteration 1
5. Implement daemon log redirect to session directory -- Owner: developer -- Due: construction iteration 2
6. Build CI test gate for three-way dispatch symmetry -- Owner: test-engineer -- Due: construction iteration 1

**Not Addressed (out of scope for this synthesis):**
- Security review F-04 (mandate container boundary for no-sandbox): partially addressed in R-011 control; full seccomp profile spec deferred
- Security review F-05 (command serialization lock): acknowledged in Section 10.3 and Section 11; no new content added as the task did not request it
- Security review F-07 (Docker volume trust boundary): not requested in synthesis scope
- Test review recommendations 4-6 (performance baselines, structured exception, CI test matrix): captured in testability subsection as architectural constraints but not expanded into full specifications

## Final Status

**Document Status:** BASELINED
**Output Location:** `/mnt/dev-inbox/fathyb/carbonyl/.aiwg/architecture/software-architecture-doc.md`
**Working Drafts:** `/mnt/dev-inbox/fathyb/carbonyl/.aiwg/working/architecture/` (3 review files preserved)
**Next Steps:** Construction phase implementation of security controls (iteration 1) and observability fixes (iteration 2)
