# issues #177, #184, #278 - SSH/PuTTY terminal input cluster

This harness covers the deterministic local pieces of the SSH/PuTTY input
cluster:

- #177: input while running Carbonyl through an SSH terminal.
- #184: mouse reports from PuTTY-class terminals.
- #278: hyperlink clicks over SSH, reported from Termux/Konsole to Debian.

The cluster is not closeable from parser tests alone. The open issue acceptance
gate still requires real terminal-environment evidence from SSH and PuTTY-style
clients. This directory records the local checks and the manual smoke matrix so
the remaining environment validation is reproducible.

## Local automated checks

Run:

```bash
./run.sh
```

The script verifies:

- SGR 1006 mouse reports decode for down/up/move/wheel and split reads.
- Legacy `CSI M Cb Cx Cy` mouse reports decode for PuTTY-compatible fallback
  paths.
- Terminal setup still enables DECSET 1002, 1003, and 1006 mouse modes.
- Existing PTY runtime smokes for right-click (#199) and Shift+Tab/modifiers
  (#237) are available; if `CARBONYL_BIN` points at an executable runtime, the
  script runs them too and reports their pass/fail status. These sibling smokes
  are advisory for this cluster because they can fail on unrelated runtime
  behavior such as forward Tab focus.

## Manual terminal smoke matrix

Use a runtime built from the same tree as the local checks.

| Client | Path | Required evidence |
|---|---|---|
| PuTTY on Windows | SSH to a Linux host, run Carbonyl interactively | Link or button click fires; no junk mouse bytes remain after exit |
| Konsole on Linux | SSH to Debian host, run Carbonyl interactively | SGR click on a fixture link navigates or activates the link |
| Termux on Android | SSH to Debian host, run Carbonyl interactively | Touch/click translation activates the fixture link |
| tmux over SSH | SSH into host, run Carbonyl inside tmux with mouse on | Keyboard input and hyperlink/button clicks still reach the page |

Suggested fixture:

```html
<!doctype html>
<title>ssh-input-ready</title>
<a id="target" href="#clicked" onclick="document.title='ssh-input-clicked'">click</a>
<input id="field" autofocus>
<script>
  field.addEventListener('input', () => document.title = 'ssh-input-typed:' + field.value);
</script>
```

Record the client, host OS, terminal settings, Carbonyl commit, and whether the
title changes after typing and clicking. Close #177/#184/#278 only after this
real-environment evidence is present.
