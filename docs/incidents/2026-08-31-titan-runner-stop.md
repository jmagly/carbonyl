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
