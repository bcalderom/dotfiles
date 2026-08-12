#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: tds [--root PATH] [--depth N] [--layout NAME]
       tds --directory PATH [--layout NAME] [--opencode-session ID] [--new-session]

Options:
  --root PATH   Search root directory (default: current directory)
  --depth N     Depth of the initial directory listing (default: 2).
                Typing in fzf searches the whole tree at any depth.
  -l, --layout NAME   Layout to use (default: 3-panes-ide)
  --directory PATH    Open PATH directly without the directory picker.
  --opencode-session ID
                Resume an OpenCode session in the selected directory.
  --new-session Create and switch to a new tmux session.
  --debug       Print tmux layout debug info
  -h, --help    Show this help

The tmux session is renamed to oc-<directory>. If zoxide is installed,
frecent directories are listed first and the selection is recorded.

Picker keys:
  enter: select · ctrl-d: enter dir · ctrl-u: go up · esc: cancel

Layouts:
  3-panes-ide
  oc
EOF
}
