# sesh-sessions

## Purpose

Shared sesh/tmux picker scripts used from shell and tmux key bindings.

## Usage

This file is sourced from `.zshrc`:

```bash
source "$HOME/scripts/tmux/sesh-sessions/sesh-sessions"
```

`Alt-S` runs the same `sesh-menu` inside and outside tmux. Inside tmux it
fills the configured popup; outside tmux it renders as a centered 75% x 60%
picker. Its views are:

| Key      | View           |
| -------- | -------------- |
| `Ctrl-A` | All sources    |
| `Ctrl-T` | Tmux sessions  |
| `Ctrl-O` | Actions        |
| `Ctrl-G` | Configurations |
| `Ctrl-X` | Projects       |
| `Ctrl-F` | Find directory |
| `Ctrl-E` | Open directory in the default file manager and close the picker |
| `Alt-K`  | Scroll preview up |
| `Alt-J`  | Scroll preview down |
| `Ctrl-/` | Open preview in `less`; use `/`, `n`, `N` to search |

Configured actions use semantic icons for terminal, Vim, development,
SSH, notes and files. Configuration and active tmux entries retain the
standard sesh icons. Project lists show at most the five highest-ranked
zoxide directories; the free directory search remains unrestricted.
Directory previews use `eza -alg --color=always --group-directories-first`.
The header changes with the focused row so directory-only and tmux-only
actions are shown only when applicable.

## Dependencies

Requires `sesh`, `tmux`, `fzf`, `fd`, `eza`, `less` and `setsid` from
`util-linux`. Opening directories graphically uses `xdg-open`, with `gio open`
as fallback. The opener is detached from the tmux popup before the picker
closes.

## Tests

```bash
bash scripts/tests/test-sesh-menu.sh
bash scripts/tests/test-sesh-open-detach.sh
```
