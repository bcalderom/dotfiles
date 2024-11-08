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

