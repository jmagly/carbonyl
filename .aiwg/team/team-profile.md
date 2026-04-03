# Team Profile — Carbonyl Automation Layer

**Project**: Carbonyl Automation Layer
**Date**: 2026-04-03

## Team Composition

| Role | Person | Responsibilities |
|------|--------|-----------------|
| Developer / Operator | Joseph Magly (roctinam) | Design, implementation, testing, deployment, and ongoing operation |
| Consumer (non-human) | LLM agents | Web task execution via the automation API; no contribution to development |

This is a solo project. There are no other human contributors.

## Skills Coverage

| Skill Area | Coverage | Gap |
|-----------|----------|-----|
| Python (core language) | Full | None |
| Terminal emulation / PTY | Full — pexpect + pyte in active use | None |
| Browser automation | Full — all four modules working | |
| Bot-detection evasion | Partial — UA, HTTP/2, webdriver flag, mouse entropy covered | JA3/TLS fingerprint not spoofed |
| Automated testing | None | Zero test coverage; no CI harness |
| Linux systems / Unix IPC | Full — fork, setsid, Unix sockets, PTY all in use | None |
| Security / threat modeling | Partial — threats identified in SAD; mitigations partially implemented | Socket peer-credential check, session dir chmod not yet enforced |
| Packaging / distribution | None | No packaging; imported as a local module |

## Communication

Work is tracked informally. The primary record of intent and design decisions is the `.aiwg/` documentation tree (intake form, SAD, requirements). Day-to-day decisions are made by the sole developer without review. There are no standups, no sprint reviews, no issue tracker in active use for this component. The git log is the only change history.

## Onboarding

A new contributor would need:

1. **Platform**: Linux x86_64 with a PTY. Not Windows, not WSL without a PTY wrapper.
2. **Runtime**: Python 3.11+, `pexpect==4.9.0`, `pyte==0.8.2`.
3. **Carbonyl binary**: Either the pre-built binary at `build/pre-built/<triple>/carbonyl` or Docker (`fathyb/carbonyl`) as fallback.
4. **Code orientation**: Read `automation/browser.py` first — it is the core class. `daemon.py`, `session.py`, and `screen_inspector.py` are supporting layers. The SAD at `.aiwg/architecture/software-architecture-doc.md` covers the full architecture.
5. **Key invariant**: All public coordinates are 1-indexed. The pyte buffer is 0-indexed internally. Getting this wrong breaks click accuracy silently.
6. **No tests to run**: There are none. Manual exercise against a target site is the only current verification path.

## Capacity

One developer, part-time. Rough estimate: 4–8 hours per week available for this component, depending on other priorities. The codebase is small (~1,720 LoC across four files) so meaningful work is achievable in short sessions. The main bottleneck for new features is the absence of a test harness — changes to coordinate math or daemon lifecycle require manual end-to-end verification.
