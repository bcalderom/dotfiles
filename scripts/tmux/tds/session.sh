#!/usr/bin/env bash

next_session_name() {
  local directory="$1"
  local base candidate n

  base="oc-$(basename -- "$directory")"
  base="${base//[.:]/-}"
  candidate="$base"
  n=2

  while tmux has-session -t "$candidate" 2>/dev/null; do
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
  local target command

  target="$(next_session_name "$DIR")"
  command="PATH=$(escape_shell "$PATH") $(escape_shell "$SELF") --directory $(escape_shell "$DIR") --layout $(escape_shell "$LAYOUT")"

  if [[ -n "$OPENCODE_SESSION" ]]; then
    command+=" --opencode-session $(escape_shell "$OPENCODE_SESSION")"
  fi

  tmux new-session -d -s "$target" -n opencode -c "$DIR"
  tmux send-keys -t "$target:opencode" "$command" C-m

  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$target" 2>/dev/null || true
  else
    exec tmux attach-session -t "$target"
  fi
}
