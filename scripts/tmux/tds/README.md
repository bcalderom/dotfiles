# tds

## Purpose

Open a selected directory in a tmux development session layout.

## Usage

```bash
tds
tds --root ~/Desarrollos
tds --root ~/Desarrollos --depth 3 --layout oc
```

The directory picker (fzf) starts with subdirectories up to `--depth`
levels (default: 2). Typing a query searches the **whole tree at any
depth** (AND semantics for multiple words). After selecting a
directory, the tmux session is renamed to `oc-<directory>` (a numeric
suffix is added on name collisions).

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

```bash
bash tests/test-tds.sh
```
