# Titan host-runner stop during Chromium validation

**Incident:** Carbonyl #299

**Window:** 2026-08-31 20:49:37–20:49:51 UTC

**Host:** Titan

## Finding

Run 49392 job 141692 did not take the host runner offline by crashing it. The runner was explicitly and cleanly stopped through systemd one second after the `storage_flush_unittests` build step began.

Correlated journal evidence:

```text
16:49:38 sudo: roctinam ... COMMAND=/usr/bin/systemctl stop gitea-runner-host.service
16:49:38 systemd: Stopping gitea-runner-host.service...
16:49:38 act_runner: shutdown initiated, waiting 5m0s for running jobs
16:49:51 systemd: gitea-runner-host.service: Deactivated successfully.
16:49:51 systemd: Consumed 3h 6min CPU over 3h 58min wall; 25.5G memory peak; 621.4M swap peak.
```

There were no kernel OOM, killed-process, Docker-daemon restart, containerd restart, or runner crash records in the 16:40–17:05 EDT journal window. Gitea's exit `-1` and offline runner state were consequences of the operator-initiated service stop.

This corrects the original causal hypothesis for job 141692. It does not invalidate the separate resource-saturation observation: a later unrestricted Ninja run reached load 107 and left about 6.1 GiB available, while the same graph at `-j4` restored more than 50 GiB available and completed. Titan therefore still needs a hard resource boundary because it is an interactive workstation.

## Corrective controls

- Clamp every default and requested Ninja value to `-j4`.
- Limit heavy build containers to four CPUs, 40 GiB RAM, and 48 GiB RAM+swap.
- Bound `gclient sync` to the same job count.
- Refuse to reset the persistent Chromium checkout when tracked operator changes exist.
- Do not execute Carbonyl/Chromium, CDP, display, input, or GPU acceptance on Titan.
- Validate checksummed artifacts in the disposable Ubuntu 26.04 `browser-qa` VM.

The host-runner service must remain stopped while any queued run created from the old unbounded workflow can still be claimed.

## 2026-09-01 quarantine recurrence

The host runner was started outside the remediation session at 16:34:41 EDT.
Eight seconds later it claimed `carbonyl-agent` run 49783/job 142349, whose E2E
suite executed the real Carbonyl browser inside the host-runner container. The
browser refused to start because the job ran as root without a supported
sandbox; 11 browser-backed tests failed. The runner continued claiming queued
work until it was stopped again at 16:59:52 and became inactive at 17:00:11.

The second service window consumed 9 minutes 51 seconds of CPU over 25 minutes
29 seconds of wall time, with a 3.8 GiB memory peak and negligible swap. Its
logs also contain repeated permission-denied cleanup failures for root-owned
host-executor files. This recurrence is not evidence of an Ubuntu 26.04 or
Wayland incompatibility: the failing browser jobs were knowingly running in the
wrong host/container security context. It does prove that merely queueing old
browser jobs is unsafe while the host runner can be restarted. Keep the service
inactive until those workflows are migrated to the disposable Ubuntu 26.04
guest or otherwise made incapable of executing Chromium on Titan.
