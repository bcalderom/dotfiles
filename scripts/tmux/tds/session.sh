#!/usr/bin/env bash

next_session_name() {
  local directory="$1"
  local base candidate n

  base="oc-$(basename -- "$directory")"
  base="${base//[.:]/-}"
  candidate="$base"
  n=2

  while tmux has-session -t "=$candidate" 2>/dev/null; do
    candidate="$base-$((n++))"
  done

  printf '%s' "$candidate"
}

rename_for_directory() {
  local directory="$1"
  local current suffix target

  current="$(tmux display-message -p '#{session_name}')"
  target="oc-$(basename -- "$directory")"
  target="${target//[.:]/-}"

  if [[ "$current" == "$target" ]]; then
    return
  fi

  suffix="${current#"$target"-}"
  if [[ "$current" == "$target-"* && "$suffix" =~ ^[0-9]+$ ]]; then
    return
  fi

  target="$(next_session_name "$directory")"
  debug_log "Renaming session ${current} to ${target}"
  tmux rename-session -t "$current" "$target"
}

create_new_session() {
  local target

  target="$(next_session_name "$DIR")"
  CURRENT_PANE_ID="$(tmux new-session -d -s "$target" -n opencode -c "$DIR" \
    -e "PATH=$PATH" -P -F '#{pane_id}')"
  WINDOW_PANES=1

  if [[ -n "$OPENCODE_SESSION" ]]; then
    tmux set-option -t "$CURRENT_PANE_ID" @opencode_session_id "$OPENCODE_SESSION"
  fi

  if have zoxide; then
    zoxide add "$DIR" 2>/dev/null || true
  fi
  apply_layout

  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "=$target"
  else
    exec tmux attach-session -t "=$target"
  fi
}
