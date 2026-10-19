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
Nothing is uninstalled. The setup does not partition disks or restore credentials.

Official packages use a full `pacman -Syu --needed` transaction. AUR packages are
reported separately (exit 1 when left pending). After reviewing and installing
yay or paru, run as your normal user, for example:

```bash
bash setup.sh --aur yay --enable-services --stow
bash setup.sh --check --enable-services --stow
```

Services and dotfile linking are opt-in. No services are started, and Stow must
pass a conflict simulation before linking. Repeat any custom group selection
when running `--check`. See the guide for plugins and host-specific manual steps.

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
