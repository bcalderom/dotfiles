#!/usr/bin/env bash
# Layout helpers for tds. Sourced by tds; expects: DIR, LAYOUT, DEBUG,
# CURRENT_PANE_ID, WINDOW_PANES, LEFT_PERCENT, RIGHT_PERCENT,
# RIGHT_TOP_PERCENT, RIGHT_BOTTOM_PERCENT and die/debug_log/escape_shell/have.

validate_percent() {
  local value="$1"
  local name="$2"

  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    die "${name} must be an integer percentage."
  fi

  if ((value < 1 || value > 99)); then
    die "${name} must be between 1 and 99."
  fi
}

pane_size() {
  tmux display-message -p -t "$1" '#{pane_width}x#{pane_height}' 2>/dev/null
}

window_size() {
  tmux display-message -p -t "$1" '#{window_width}x#{window_height}' 2>/dev/null
}

opencode_command() {
  local command="opencode"

  if [[ -n "${OPENCODE_SESSION:-}" ]]; then
    command+=" --session $(escape_shell "$OPENCODE_SESSION")"
  fi

  printf '%s' "$command"
}

run_in_directory() {
  local pane="$1"
  local command="${2:-}"
  local current_directory

  current_directory="$(tmux display-message -p -t "$pane" '#{pane_current_path}')"
  if [[ "$current_directory" != "$DIR" && ! "$current_directory" -ef "$DIR" ]]; then
    command="builtin cd -- $(escape_shell "$DIR")${command:+ && $command}"
  fi

  [[ -z "$command" ]] || tmux send-keys -t "$pane" "$command" C-m
}

split_pane() {
  local target="$1"
  local orientation="$2"
  local percent="$3"
  local pane
  local pane_dims
  local window_dims

  pane_dims="$(pane_size "${target}")"
  window_dims="$(window_size "${target}")"
  debug_log "Splitting ${target} ${orientation} ${percent}% (pane ${pane_dims}, window ${window_dims})"

  if ! pane="$(tmux split-window -t "${target}" "${orientation}" -p "${percent}" -P -F '#{pane_id}' -c "${DIR}")"; then
    window_dims="$(window_size "${target}")"
    pane_dims="$(pane_size "${target}")"
    debug_log "Split failed for ${target} (pane ${pane_dims}, window ${window_dims})"
    echo "Window too small for requested layout. Resize and retry." >&2
    exit 1
  fi

  printf '%s' "${pane}"
}

validate_layout() {
  case "${LAYOUT}" in
  3-panes-ide)
    require_apps nvim
    validate_percent "${LEFT_PERCENT}" "LEFT_PERCENT"
    validate_percent "${RIGHT_PERCENT}" "RIGHT_PERCENT"
    validate_percent "${RIGHT_TOP_PERCENT}" "RIGHT_TOP_PERCENT"
    validate_percent "${RIGHT_BOTTOM_PERCENT}" "RIGHT_BOTTOM_PERCENT"

    if ((LEFT_PERCENT + RIGHT_PERCENT != 100)); then
      die "LEFT_PERCENT and RIGHT_PERCENT must sum to 100."
    fi

    if ((RIGHT_TOP_PERCENT + RIGHT_BOTTOM_PERCENT != 100)); then
      die "RIGHT_TOP_PERCENT and RIGHT_BOTTOM_PERCENT must sum to 100."
    fi
    ;;
  oc)
    ;;
  *)
    die "Unknown layout: ${LAYOUT}. Valid layouts: 3-panes-ide, oc"
    ;;
  esac
}

layout_3_panes_ide() {
  local left_pane="${CURRENT_PANE_ID}"
  local right_pane
  local bottom_right_pane
  local top_right_pane

  if [[ "${WINDOW_PANES}" -gt 1 ]]; then
    tmux kill-pane -a -t "${left_pane}"
  fi

  right_pane="$(split_pane "${left_pane}" -h "${RIGHT_PERCENT}")"
  bottom_right_pane="$(split_pane "${right_pane}" -v "${RIGHT_BOTTOM_PERCENT}")"
  top_right_pane="${right_pane}"
  run_in_directory "$left_pane" "$(opencode_command)"
  run_in_directory "$top_right_pane" 'nvim -c "Telescope find_files"'
  run_in_directory "$bottom_right_pane"

  tmux select-pane -t "${left_pane}"
}

layout_oc() {
  local left_pane="${CURRENT_PANE_ID}"

  if [[ "${WINDOW_PANES}" -gt 1 ]]; then
    tmux kill-pane -a -t "${left_pane}"
  fi

  run_in_directory "$left_pane" "$(opencode_command)"
  tmux select-pane -t "${left_pane}"
}

apply_layout() {
  case "${LAYOUT}" in
  3-panes-ide)
    layout_3_panes_ide
    ;;
  oc)
    layout_oc
    ;;
  esac
}
