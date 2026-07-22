#!/usr/bin/env bash

INTERNAL="eDP-1"
EXTERNAL="DP-1"
HDMI="HDMI-A-1"
STATE="${1:-}"
LID_STATE_PATH="${LID_STATE_PATH:-}"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-lid.lock"
ACTIVE_WORKSPACE_FILE="${HYPR_LID_ACTIVE_WORKSPACE_FILE:-${XDG_RUNTIME_DIR:-/tmp}/hypr-lid-active-workspace}"
AUDIO_ROUTE_SCRIPT="${HYPR_LID_AUDIO_ROUTE_SCRIPT:-${HOME}/.config/kanshi/audio-route.sh}"

command -v hyprctl >/dev/null 2>&1 || exit 0

if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE" || exit 0
  flock -n 9 || exit 0
fi

lid_is_closed() {
  if [ -n "$LID_STATE_PATH" ]; then
    grep -q closed "$LID_STATE_PATH" 2>/dev/null
  else
    grep -q closed /proc/acpi/button/lid/*/state 2>/dev/null
  fi
}

if [ -z "$STATE" ]; then
  if lid_is_closed; then
    STATE="closed"
  else
    STATE="open"
  fi
fi

monitors_all() {
  hyprctl monitors all 2>/dev/null || hyprctl monitors 2>/dev/null || true
}

monitor_known() {
  monitors_all | grep -q "^Monitor $1 "
}

monitor_active() {
  hyprctl monitors 2>/dev/null | grep -q "^Monitor $1 "
}

external_available() {
  monitor_known "$EXTERNAL"
}

hdmi_available() {
  monitor_known "$HDMI"
}

internal_available() {
  monitor_active "$INTERNAL"
}

wait_for_monitor() {
  local monitor="$1"
  local i=0

  while [ "$i" -lt 30 ]; do
    monitor_active "$monitor" && return 0
    sleep 0.1
    i=$((i + 1))
  done

  return 1
}

enable_external() {
  if ! monitor_active "$EXTERNAL"; then
    hyprctl keyword monitor "$EXTERNAL,2560x1440@120.01,1920x0,1" >/dev/null 2>&1 || true
  fi
  wait_for_monitor "$EXTERNAL"
}

enable_internal() {
  if ! monitor_active "$INTERNAL"; then
    hyprctl keyword monitor "$INTERNAL,preferred,0x0,1" >/dev/null 2>&1 || true
  fi
  hyprctl dispatch dpms on "$INTERNAL" >/dev/null 2>&1 || true
  wait_for_monitor "$INTERNAL"
}

disable_hdmi() {
  monitor_active "$HDMI" || return 0
  hyprctl keyword monitor "$HDMI,disable" >/dev/null 2>&1 || true
}

route_audio() {
  [ -x "$AUDIO_ROUTE_SCRIPT" ] || return 0
  "$AUDIO_ROUTE_SCRIPT" >/dev/null 2>&1 || true
}

active_workspace() {
  hyprctl activeworkspace 2>/dev/null | awk '/^workspace ID/ { print $3; exit }'
}

workspace_ids() {
  hyprctl workspaces 2>/dev/null | awk '$1 == "workspace" && $2 == "ID" && $3 ~ /^[0-9]+$/ { print $3 }'
}

workspace_ids_on_monitor() {
  hyprctl workspaces 2>/dev/null | awk -v monitor="$1" '
    $1 == "workspace" && $2 == "ID" && $3 ~ /^[0-9]+$/ {
      workspace_monitor = $7
      sub(/:$/, "", workspace_monitor)
      if (workspace_monitor == monitor) print $3
    }'
}

workspace_ids_on_monitor_with_windows() {
  hyprctl workspaces 2>/dev/null | awk -v monitor="$1" '
    $1 == "workspace" && $2 == "ID" && $3 ~ /^[0-9]+$/ {
      workspace = $3
      workspace_monitor = $7
      sub(/:$/, "", workspace_monitor)
      candidate = workspace_monitor == monitor
    }
    candidate && $1 == "windows:" && $2 > 0 { print workspace; candidate = 0 }'
}

workspace_on_monitor() {
  hyprctl workspaces 2>/dev/null | awk -v workspace="$1" -v monitor="$2" '
    $1 == "workspace" && $2 == "ID" && $3 == workspace {
      workspace_monitor = $7
      sub(/:$/, "", workspace_monitor)
      found = workspace_monitor == monitor
    }
    END { exit found ? 0 : 1 }'
}

next_workspace_after_monitor() {
  workspace_ids_on_monitor "$1" | awk 'max < $1 { max = $1 } END { print max + 1 }'
}

next_docked_open_workspace() {
  {
    printf '%s\n' 1 2
    workspace_ids_on_monitor_with_windows "$EXTERNAL"
  } | awk 'max < $1 { max = $1 } END { print max + 1 }'
}

recorded_workspace() {
  [ -f "$ACTIVE_WORKSPACE_FILE" ] || return 0
  awk 'NR == 1 && $1 ~ /^[0-9]+$/ { print $1; exit }' "$ACTIVE_WORKSPACE_FILE" 2>/dev/null
}

bind_workspace() {
  hyprctl keyword workspace "$1,monitor:$2" >/dev/null 2>&1 || true
}

bind_nonpersistent_workspace() {
  hyprctl keyword workspace "$1,monitor:$2,persistent:false" >/dev/null 2>&1 || true
}

bind_existing_workspaces() {
  local target="$1"

  workspace_ids | while IFS= read -r workspace; do
    bind_nonpersistent_workspace "$workspace" "$target"
  done
}

move_workspace() {
  hyprctl dispatch moveworkspacetomonitor "$1" "$2" >/dev/null 2>&1 || true
}

move_existing_workspaces() {
  local target="$1"

  workspace_ids | while IFS= read -r workspace; do
    move_workspace "$workspace" "$target"
  done
}

restore_workspace() {
  [ -n "$1" ] || return 0
  hyprctl dispatch workspace "$1" >/dev/null 2>&1 || true
}

move_main_workspaces() {
  local target="$1"
  local current_ws="${2:-}"

  bind_existing_workspaces "$target"
  bind_workspace 1 "$target"
  bind_workspace 2 "$target"
  bind_nonpersistent_workspace 3 "$target"

  move_existing_workspaces "$target"
  move_workspace 1 "$target"
  move_workspace 2 "$target"
  move_workspace 3 "$target"

  if [ -n "$current_ws" ]; then
    move_workspace "$current_ws" "$target"
  fi
}

configure_docked_open_workspaces() {
  local current_ws="${1:-}"
  local internal_ws="${2:-}"
  local restore_current="${3:-0}"

  [ -n "$internal_ws" ] || internal_ws="$(next_workspace_after_monitor "$EXTERNAL")"

  workspace_ids_on_monitor "$EXTERNAL" | while IFS= read -r workspace; do
    bind_nonpersistent_workspace "$workspace" "$EXTERNAL"
  done
  bind_workspace 1 "$EXTERNAL"
  bind_workspace 2 "$EXTERNAL"
  bind_nonpersistent_workspace "$internal_ws" "$INTERNAL"

  move_workspace 1 "$EXTERNAL"
  move_workspace 2 "$EXTERNAL"
  restore_workspace "$internal_ws"
  move_workspace "$internal_ws" "$INTERNAL"

  if [ "$restore_current" -eq 1 ] || [ "$current_ws" = "$internal_ws" ]; then
    restore_workspace "$current_ws"
  fi
}

case "$STATE" in
  closed|close)
    current_ws="$(active_workspace)"

    i=0
    while [ "$i" -lt 30 ]; do
      if external_available; then
        break
      fi
      sleep 0.1
      i=$((i + 1))
    done

    if external_available; then
      if enable_external; then
        disable_hdmi
        move_main_workspaces "$EXTERNAL" "$current_ws"
        hyprctl keyword monitor "$INTERNAL,disable" >/dev/null 2>&1 || true
        restore_workspace "$current_ws"
        route_audio
      fi
    fi
    ;;
  open)
    current_ws="$(active_workspace)"
    current_ws_on_external=0
    if workspace_on_monitor "$current_ws" "$EXTERNAL"; then
      current_ws_on_external=1
    fi
    internal_ws="$(next_docked_open_workspace)"

    if external_available; then
      enable_external || exit 0
      disable_hdmi
      enable_internal || exit 0
    elif hdmi_available; then
      enable_internal || exit 0
      hyprctl keyword monitor "$HDMI,1920x1080@60,0x0,1,mirror,$INTERNAL" >/dev/null 2>&1 || true
    else
      enable_internal || exit 0
    fi

    if internal_available; then
      if external_available; then
        configure_docked_open_workspaces "$current_ws" "$internal_ws" "$current_ws_on_external"
      else
        restore_ws="$(recorded_workspace)"
        [ -n "$restore_ws" ] || restore_ws="$current_ws"
        move_main_workspaces "$INTERNAL" "$restore_ws"
        restore_workspace "$restore_ws"
      fi
      route_audio
    fi
    ;;
esac
