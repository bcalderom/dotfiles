# scripts tests

## Purpose

Cross-cutting tests for the `scripts/` tree.

Command-specific tests live beside their command under each command's `tests/` directory.

## Usage

```bash
bash test-script-structure.sh
bash test-quick-menu.sh
bash test-setup.sh
```

`test-setup.sh` checks the root Arch bootstrapper with mocked pacman, AUR helpers,
hardware detection, systemd and Stow, using a temporary HOME. It covers read-only
modes, hardware profiles, opt-in groups, repeatable installs and failure handling
without installing packages, accessing the network or changing host services.
When Stow is installed and the test runs as a normal user, it also checks real
symlink creation and conflicts inside a generated checkout and temporary HOME.
It also covers opt-in config migration, its private-data consent and previews,
and config-only runs that must not install packages or enable services.
Hardware flags are tested with mocked deployers: previews/checks stay read-only,
missing AUR packages cannot activate Kanata, and lid preflight failures prevent
package installation. Real Stow fixtures also exclude host-specific lid drop-ins.

Hardware deployers have isolated tests (from the repository root):

```bash
bash scripts/keyboard/kanata-deploy/tests/test-kanata-deploy.sh
bash scripts/desktop/hypr-lid-deploy/tests/test-configure-host.sh
```

They use temporary HOME/system/hardware roots and mocked systemd; they never
capture a keyboard, write `/etc`, suspend a machine or restart real services.

The config migration helper has its own synthetic-fixture tests:

```bash
python3 -B scripts/system/migrate-app-configs/tests/test_migrate_app_configs.py
```

Run that command from the repository root. No real profiles or SSH connections
are used; real rsync integration is limited to a generated temporary HOME.

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
