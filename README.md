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

## OBS setup script

Use the OBS helper script in `scripts/obs/setup-obs.sh` to verify/install the
minimum requirements for screen capture, audio capture, and webcam on Arch Linux.

```bash
bash scripts/obs/setup-obs.sh
```

Useful flags:

```bash
bash scripts/obs/setup-obs.sh --check-only
bash scripts/obs/setup-obs.sh --dry-run
```
