---
title: CI/CD Scaffold — Carbonyl Automation Layer
version: "1.0"
date: 2026-04-03
scope: automation/ module
status: DRAFT
---

# CI/CD Scaffold — Carbonyl Automation Layer

**Version**: 1.0
**Date**: 2026-04-03
**Scope**: `automation/` module — Python 3.11 library wrapping the Carbonyl binary

---

## 1. Pipeline Overview

The pipeline has three stages that run in order on every push to `main` and on every pull request targeting `main`.

| Stage | Trigger | What Runs | Carbonyl Binary Needed |
|-------|---------|-----------|------------------------|
| **lint** | Every push / PR | ruff (or flake8) | No |
| **test** | After lint passes | Unit + integration (pytest) | No |
| **build** | After tests pass | Validation only — no artifact | No |

A fourth stage, **e2e**, is opt-in. It runs only when the PR carries an `[e2e]` label or when triggered manually via `workflow_dispatch`. It requires the Carbonyl binary and is the release gate for Construction → Transition, not for routine PRs.

**Note on the carbonyl binary**: This CI does not build carbonyl. It is a pre-built dependency resolved from `build/pre-built/<triple>/carbonyl` at runtime. The binary must be provided to the E2E runner as a downloaded artifact or via a runner with the binary pre-installed. Standard CI jobs (lint, test, build) run without it.

---

## 2. Gitea Actions Workflow

Save this file as `/.gitea/workflows/ci.yml` in the repository root.

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      run_e2e:
        description: "Run E2E tests"
        type: boolean
        default: false

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python 3.11
        uses: actions/setup-python@v4
        with:
          python-version: "3.11"

      - name: Install lint dependencies
        run: pip install ruff

      - name: Run ruff
        run: ruff check automation/

  test:
    name: Test (unit + integration)
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python 3.11
        uses: actions/setup-python@v4
        with:
          python-version: "3.11"

      - name: Install dependencies
        run: pip install -e ".[dev]"

      - name: Run unit and integration tests
        run: |
          pytest automation/tests/ \
            --ignore=automation/tests/e2e \
            --cov=automation \
            --cov-branch \
            --cov-report=term-missing \
            --cov-fail-under=80 \
            -v

  build:
    name: Build (validate)
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python 3.11
        uses: actions/setup-python@v4
        with:
          python-version: "3.11"

      - name: Verify package installs cleanly
        run: |
          pip install build
          python -m build --sdist --wheel
          pip install dist/*.whl

  e2e:
    name: E2E (gated)
    runs-on: ubuntu-latest
    needs: test
    if: |
      contains(github.event.pull_request.labels.*.name, 'e2e') ||
      github.event_name == 'workflow_dispatch' && inputs.run_e2e == true
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python 3.11
        uses: actions/setup-python@v4
        with:
          python-version: "3.11"

      - name: Install dependencies
        run: pip install -e ".[dev]"

      - name: Resolve carbonyl binary
        run: |
          TRIPLE=$(bash scripts/platform-triple.sh)
          BINARY=build/pre-built/${TRIPLE}/carbonyl
          if [ ! -x "$BINARY" ]; then
            echo "carbonyl binary not found at $BINARY — E2E cannot run"
            exit 1
          fi
          echo "Using binary: $BINARY"

      - name: Run E2E tests
        run: |
          pytest automation/tests/e2e/ -v --timeout=120
```

---

## 3. E2E Tier Requirements

The `e2e` job has requirements that the standard lint and test jobs do not:

- **Carbonyl binary**: must be present at `build/pre-built/<platform-triple>/carbonyl` and executable. The binary is resolved by `scripts/platform-triple.sh`. It is not downloaded or built by CI — it must be supplied by the runner environment or checked in for the target platform.
- **Linux x86_64 runner**: `os.fork()`, PTY, and Unix domain sockets are required (SAD Section 10.4). macOS is untested; Windows is unsupported.
- **Network access**: the E2E suite runs against a local `http.server` instance and does not require external network access. Do not add tests that hit live external sites — bot-detection validation (UC-005) is manual-only per the test strategy.
- **No Docker-in-Docker**: Chromium's `--no-sandbox` flag satisfies PTY operation without requiring a privileged container. DinD is not needed for this test tier.

---

## 4. Notes

- The `build` stage produces no artifact. The automation layer is a pure Python library distributed via `pip install`. The stage exists to catch packaging regressions (missing `__init__.py`, broken `pyproject.toml`, import-time errors).
- Coverage enforcement (`--cov-fail-under=80`) applies to the combined unit and integration run. Per-component thresholds defined in the test strategy (90% for ScreenInspector, 100% command coverage for `_BrowserServer._dispatch`) are enforced by pytest markers rather than a single global floor.
- The `[e2e]` label must be added manually to a PR by the reviewer who wants E2E coverage before merge. It is not set automatically.
- When the E2E job fails in CI, check the binary path first. A missing or non-executable carbonyl binary produces the same exit-1 as a failed test.
