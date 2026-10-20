# My dotfiles

This directory contains the dotfiles for my system

## Requirements

Ensure you have Git and Stow installed on your system

```bash
sudo pacman -S git stow
```

## Installation

First, check out the dotfiles repo in your $HOME directory using git

```
$ git clone --branch lenovo https://github.com/bcalderom/dotfiles.git
$ cd dotfiles
```

The current workstation configuration is on `lenovo`; the default `main` branch
may be older. Review hardware-specific settings before using it on another host.

then use GNU stow to create symlinks

```bash
$ stow .
```

The `scripts/bin` directory is the public command layer for personal scripts.
Each command lives in its own directory under `scripts/`, with its own
`README.md` and optional local `tests/` directory. `scripts/bin` contains
relative symlinks so commands stay portable when the repo is stowed on another
machine.

## Arch bootstrap and migration

For the new machine currently running Ubuntu, use the
[step-by-step Ubuntu-to-Arch installation guide](docs/arch-installation.md).
It covers the prepared ISO, disk replacement, systemd-boot/bootctl and all setup
package groups, with separate commands for the live ISO and the installed system.

For a new machine, install the Arch base system first, then follow the
[migration guide](docs/migration.md) for the official ISO, hardware checks,
package selection, data transfer over SSH, and final validation.

The new AMD machine also has a guarded [base-system installer](scripts/system/install-arch/README.md):
UEFI/GPT, 2 GiB EFI, 100 GiB ext4 root, remaining ext4 home, zram and user `boris`.
It runs only from the live ISO after explicit disk/serial confirmation. Preview
the profile safely on any host:

```bash
python3 scripts/system/install-arch/install_arch.py --example
```

Preview the packages selected from shell usage and desktop dependencies:

```bash
bash setup.sh --dry-run
bash setup.sh --dry-run --cpu amd --gpu amd --with docker,printing,office
```

The default selection covers the shell, development tools, desktop, audio,
network, Bluetooth, fonts, keyboard and VPN packages. Optional groups are added
with `--with`; `--only` selects an exact set. CPU and GPU detection are independent.
Nothing is uninstalled. The setup does not partition disks or restore credentials
by default. Chromium is in `ui`; native HeidiSQL Qt6 is in `dev` (AUR), and
`network` includes `openbsd-netcat` for the MCP SSH-tunnel wrappers.

Official packages use a full `pacman -Syu --needed` transaction. AUR packages are
reported separately (exit 1 when left pending). After reviewing and installing
yay or paru, run as your normal user, for example:

```bash
bash setup.sh --aur yay --enable-services --stow
bash setup.sh --check --enable-services --stow
```

Services and dotfile linking are opt-in. `--enable-services` starts no services, and Stow must
pass a conflict simulation before linking. Repeat any custom group selection
when running `--check`. See the guide for plugins and host-specific manual steps.

Keyboard and lid deployment are separate, explicit choices:

```bash
bash setup.sh --dry-run --aur yay --stow --deploy-kanata --configure-lid
bash setup.sh --aur yay --stow --deploy-kanata --configure-lid
bash setup.sh --check --deploy-kanata --configure-lid
```

`--deploy-kanata` validates the mapping, installs the system service/config and
uinput boot configuration, then enables/restarts Kanata. `--configure-lid` detects
the local lid sensor and backlight, reloads logind and deploys/enables/restarts the
display coordinator, never Hyprland or logind. It keeps the machine awake with
the lid closed **on battery, AC and dock**; do not leave it running in a bag.
Existing different configurations require review rather than blind replacement.
Dry runs and checks do not write files or change services. Hardware drop-ins are
host-local and excluded from Stow. No real setup runs as part of the tests.

Application settings can be migrated separately from a snapshot HOME or the old
host, without installing packages or changing dotfile links:

```bash
bash setup.sh --configs-only --copy-app-configs-from boris@OLD_HOST \
  --config-apps onlyoffice,marktext,heidisql,chromium,brave,teams-for-linux,thunderbird,spotify,opencode \
  --dry-run
```

Real copying requires closed apps on both hosts, `--include-private-configs` and
an interactive confirmation. The staged copy is checksum-verified and existing
settings are backed up before replacement. See
[application config migration](scripts/system/migrate-app-configs/README.md) for
SSH authentication, supported paths and browser keyring limitations. Private
profiles and credentials never belong in this repository.
Thunderbird includes local mail. OpenCode v2 copies global settings/definitions,
not session history, provider credentials or service registration; close its
clients and background service manually before copying.

## Terminal sessions

`Alt-S` opens the shared sesh picker from the shell or a tmux popup. It supports
project search, confirmed session deletion and resuming recent OpenCode v2
sessions with `Ctrl-R`, without redundant directory changes.

- [sesh picker: shortcuts, search, compatibility and diagnostics](scripts/tmux/sesh-sessions/README.md)
- [tds: development layouts, session creation and tests](scripts/tmux/tds/README.md)

## OBS setup script

Use the OBS helper script in `scripts/obs/setup-obs/setup-obs.sh` to verify/install the
minimum requirements for screen capture, audio capture, and webcam on Arch Linux.

```bash
bash scripts/obs/setup-obs/setup-obs.sh
```

Useful flags:

```bash
bash scripts/obs/setup-obs/setup-obs.sh --check-only
bash scripts/obs/setup-obs/setup-obs.sh --dry-run
```

## Printing diagnostics

Use `psvc` to manage local CUPS/Avahi services, run read-only printer
connectivity diagnostics, or print with per-job options that do not persist as
printer defaults.

```bash
psvc status
psvc start
psvc stop
psvc doctor --queue brother_t720dw
psvc doctor --queue brother_t720dw --strict-network
psvc print
psvc print --preset 2up-short-edge document.pdf
psvc print --dry-run --preset 2up-short-edge document.pdf
```

`psvc doctor` treats transient printer network probe failures as warnings by
default because Wi-Fi printers can sleep or answer slowly. Use
`--strict-network` when you need network probe failures to return a non-zero
status.

## Display setup docs

Laptop monitor, docked USB-C, HDMI mirror, workspace, lid, and audio behavior are documented in `docs/display-setup/`.
