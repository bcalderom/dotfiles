# scripts tests

## Purpose

Cross-cutting tests for the `scripts/` tree.

Command-specific tests live beside their command under each command's `tests/` directory.

## Usage

```bash
bash test-script-structure.sh
bash test-quick-menu.sh
```

`test-quick-menu.sh` checks the Hyprland quick menu's Docker stop action with
simulated Docker, systemd, Polkit, rofi, and notification commands. It does not
change real services or containers. Temporary fixtures live under
`${TMPDIR:-/tmp}`.

The menu opened with **Alt + Super + Space** includes **Docker: detener
servicios**. It stops local containers before stopping `docker.socket`,
`docker.service`, and `containerd.service`. Active containers require an
explicit confirmation; Cancel is selected by default. Failed container queries
or newly appearing containers abort the operation. A running containerd without
an active Docker daemon also aborts because its containers cannot be checked.
