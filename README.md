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
$ git clone git@github.com/bcalderom/dotfiles.git
$ cd dotfiles
```

then use GNU stow to create symlinks

```bash
$ stow .
```

The `scripts/bin` directory is the public command layer for personal scripts.
Each command lives in its own directory under `scripts/`, with its own
`README.md` and optional local `tests/` directory. `scripts/bin` contains
relative symlinks so commands stay portable when the repo is stowed on another
machine.

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
