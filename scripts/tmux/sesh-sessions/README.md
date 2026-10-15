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
| `Ctrl-R` | Recent OpenCode sessions |
| `F2`     | Rename the selected tmux session |
| `Ctrl-D` | Delete the selected tmux session after confirmation (Cancel is the default) |
| `Ctrl-E` | Open directory in the default file manager and close the picker |
| `Alt-K`  | Scroll preview up |
| `Alt-J`  | Scroll preview down |
| `Ctrl-/` | Open preview in `less`; use `/`, `n`, `N` to search |

Configured actions use semantic icons for terminal, Vim, development,
SSH, notes and files. Configuration and active tmux entries retain the
standard sesh icons. Entries are classified from `sesh list --json`, not by
parsing icons. Project and all-source views include every zoxide directory.

### Search and freshness

The free directory search initially shows two levels. Typing searches at any
depth with case-insensitive words (AND matching), excluding `.Trash`, `.git`,
`.cache` and `node_modules`. For example, `my-project src` finds paths containing
both words. Queries wait 150 ms before searching; other views keep fzf's fuzzy
matching. Returning to another view restores fuzzy search automatically.

List command failures propagate instead of silently appearing as an empty list.
Normal navigation uses sesh's cache; after deleting or renaming, the picker
reloads live data with `--no-cache`. Deletion requires selecting **Delete** in
the confirmation dialog; **Cancel** is selected by default and `Esc` cancels.

### OpenCode v2 sessions

The OpenCode view uses OpenCode v2's `opencode api session.list` command across
all projects and shows the ten most recently updated root sessions, excluding
archived sessions and those already open through this picker. It fetches more
pages when needed to fill the list. The command discovers or starts OpenCode's
background service; it does not require starting the OpenCode TUI first.

Selecting one creates a dedicated `oc-<directory>` tmux session through
[`tds`](../tds/README.md), resumes it in its original
directory and records the launched OpenCode session ID for filtering thereafter.
This metadata tracks what the picker launched, not subsequent session changes
made inside the OpenCode UI.

This replaces the V1 `opencode --pure db` query. `opencode session list` is not
an equivalent replacement because it lists only the current project's sessions.

### Previews

Titles and paths wrap by words to fit the popup width only in the OpenCode view.
Directory previews use `eza -alg --color=always --group-directories-first`.
An 80 ms preview delay avoids repeatedly listing directories during fast navigation.
The header changes with the focused row so directory-only and tmux-only
actions are shown only when applicable.

## Dependencies

Requires `sesh`, `tmux`, `fzf`, `fd`, `eza`, `less`, `jq`, `opencode`, `tds`
and `setsid` from `util-linux`. Opening directories graphically uses
`xdg-open`, with `gio open` as fallback. The opener is detached from the tmux
popup before the picker closes.

Validated with sesh **2.33.0** and OpenCode **2.0.29**. Sesh must support JSON
listing and `--no-cache`; the recent-session helper requires the OpenCode v2
API. It uses `/usr/bin/opencode` by default; set `OPENCODE_BIN` to select
another V2 executable.

## Diagnostics

From the repository root, inspect each data source without opening fzf:

```bash
NO_COLOR=1 scripts/tmux/sesh-sessions/sesh-menu --list home --fresh
NO_COLOR=1 scripts/tmux/sesh-sessions/sesh-menu --list projects
NO_COLOR=1 scripts/tmux/sesh-sessions/sesh-menu --list find 'my-project src'
NO_COLOR=1 scripts/tmux/sesh-sessions/sesh-menu --list recent
```

An empty successful result means there were no matching sessions or directories;
a nonzero exit indicates a command or data error. When the repo is stowed,
script changes apply to the next picker invocation without restarting tmux.

## Tests

Run from the repository root. These cover JSON classification, complete project
lists, deep word searches, cancellation, confirmations, errors, fresh reloads,
OpenCode pagination and dispatch to `sesh` or `tds`. The explorer integration
test uses a private tmux socket.

```bash
bash scripts/tests/test-sesh-menu.sh
bash scripts/tests/test-sesh-data.sh
bash scripts/tests/test-opencode-recent.sh
bash scripts/tests/test-sesh-open-detach.sh
```
