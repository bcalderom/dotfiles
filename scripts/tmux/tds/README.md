# tds

## Purpose

Open a selected directory in a tmux development session layout.

## Usage

```bash
tds
tds --root ~/Desarrollos
tds --root ~/Desarrollos --depth 3 --layout oc
tds --directory ~/Desarrollos/project --layout oc \
  --opencode-session ses_example --new-session
```

The directory picker (fzf) starts with subdirectories up to `--depth`
levels (default: 2). Typing a query searches the **whole tree at any
depth** (AND semantics for multiple words). After selecting a
directory, the tmux session is renamed to `oc-<directory>` (a numeric
suffix is added on name collisions).

`--directory` skips the picker. `--opencode-session` resumes that OpenCode
session with `opencode --session <id>` and records the ID as tmux metadata.
`--new-session` creates and switches to a new `oc-<directory>` session instead
of changing the current tmux session. These options are used by the recent
OpenCode view in `sesh-menu`.

New sessions are initialized directly, without launching `tds` a second time
inside the pane. Panes already in the selected directory do not receive another
`cd`. Reused panes change directory with `builtin cd -- ... && <command>` so
aliases cannot alter navigation and a failed change does not start an app in
the wrong directory.

Without `--new-session`, applying a layout closes the other panes in the current
tmux window. Use `--directory PATH --new-session` to preserve the current window.
The OpenCode metadata records the launched session; it does not follow session
switches made later inside OpenCode. See the
[picker documentation](../sesh-sessions/README.md) for filtering and diagnostics.

### Picker keys

| Key      | Action                                             |
| -------- | -------------------------------------------------- |
| `enter`  | Select the highlighted directory                   |
| `ctrl-d` | Enter the highlighted directory (browse deeper)    |
| `ctrl-u` | Go up to the parent directory (stops at `--root`)  |
| `esc`    | Cancel                                             |

The current root is shown in the header and the shortcuts in the
footer of the picker. zoxide frecent directories are only listed at
the initial root; after entering a directory with `ctrl-d`, the
picker shows the local subtree.

## Dependencies

Requires `tmux`, `fzf`, `fd` (or `fdfind`) and `opencode`; the
`3-panes-ide` layout also requires `nvim`. If `zoxide` is installed,
frecent directories are listed first and the selection is recorded.

## Tests

The integration tests use private tmux sockets and do not touch existing sessions.
Launch tests use mock applications and zoxide. Temporary files respect `TMPDIR`.
Run from the repository root:

```bash
bash scripts/tmux/tds/tests/test-tds.sh
bash scripts/tmux/tds/tests/test-tds-resume.sh
bash scripts/tmux/tds/tests/test-tds-launch.sh
```
