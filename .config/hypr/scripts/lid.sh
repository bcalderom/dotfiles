#!/usr/bin/env bash

INTERNAL="eDP-1"
EXTERNAL="DP-1"
HDMI="HDMI-A-1"
STATE="${1:-}"
LID_STATE_PATH="${LID_STATE_PATH:-}"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-lid.lock"

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

switch_docked_profile() {
  command -v kanshictl >/dev/null 2>&1 || return 1

  kanshictl switch docked_dp_hdmi >/dev/null 2>&1 || \
    kanshictl switch docked_dp_only >/dev/null 2>&1
}

switch_laptop_profile() {
  command -v kanshictl >/dev/null 2>&1 || return 1

  kanshictl switch laptop >/dev/null 2>&1
}

switch_mirror_profile() {
  command -v kanshictl >/dev/null 2>&1 || return 1

  kanshictl switch mirror >/dev/null 2>&1
}

switch_docked_open_profile() {
  command -v kanshictl >/dev/null 2>&1 || return 1

  kanshictl switch docked_open_dp_hdmi >/dev/null 2>&1 || \
    kanshictl switch docked_open_dp_only >/dev/null 2>&1
}

internal_available() {
  monitor_active "$INTERNAL"
}

active_workspace() {
  hyprctl activeworkspace 2>/dev/null | awk '/^workspace ID/ { print $3; exit }'
}

bind_workspace() {
  hyprctl keyword workspace "$1,monitor:$2" >/dev/null 2>&1 || true
}

bind_persistent_workspace() {
  hyprctl keyword workspace "$1,monitor:$2,persistent:true" >/dev/null 2>&1 || true
}

move_workspace() {
  hyprctl dispatch moveworkspacetomonitor "$1" "$2" >/dev/null 2>&1 || true
}

restore_workspace() {
  [ -n "$1" ] || return 0
  hyprctl dispatch workspace "$1" >/dev/null 2>&1 || true
}

wait_for_internal() {
  local i=0

  while [ "$i" -lt 30 ]; do
    if internal_available; then
      break
    fi
    sleep 0.1
    i=$((i + 1))
  done
}

move_main_workspaces() {
  local target="$1"
  local current_ws="${2:-}"

  bind_workspace 1 "$target"
  bind_workspace 2 "$target"
  bind_persistent_workspace 3 "$target"

  move_workspace 1 "$target"
  move_workspace 2 "$target"
  move_workspace 3 "$target"

  if [ -n "$current_ws" ]; then
    move_workspace "$current_ws" "$target"
  fi
}

configure_docked_open_workspaces() {
  local current_ws="${1:-}"

  bind_workspace 1 "$EXTERNAL"
  bind_workspace 2 "$EXTERNAL"
  bind_persistent_workspace 3 "$INTERNAL"

  move_workspace 1 "$EXTERNAL"
  move_workspace 2 "$EXTERNAL"
  move_workspace 3 "$INTERNAL"

  restore_workspace "$current_ws"
}

reload_waybar() {
  command -v pgrep >/dev/null 2>&1 || return 0
  pgrep -x waybar >/dev/null 2>&1 || return 0
  hyprctl dispatch exec "bash -lc 'pkill -x waybar >/dev/null 2>&1 || true; waybar'" >/dev/null 2>&1 || true
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
      switch_docked_profile || true

      move_main_workspaces "$EXTERNAL" "$current_ws"
      hyprctl keyword monitor "$INTERNAL,disable" >/dev/null 2>&1 || true
      restore_workspace "$current_ws"
      reload_waybar
    fi
    ;;
  open)
    current_ws="$(active_workspace)"

    if external_available || hdmi_available; then
      internal_monitor="$INTERNAL,preferred,0x0,1"
    else
      internal_monitor="$INTERNAL,preferred,auto,1"
    fi

    hyprctl keyword monitor "$internal_monitor" >/dev/null 2>&1 || true
    hyprctl dispatch dpms on "$INTERNAL" >/dev/null 2>&1 || true

    if external_available; then
      switch_docked_open_profile || true
    elif hdmi_available; then
      switch_mirror_profile || true
      hyprctl keyword monitor "$HDMI,1920x1080@60,0x0,1,mirror,$INTERNAL" >/dev/null 2>&1 || true
    else
      switch_laptop_profile || true
    fi

    hyprctl keyword monitor "$internal_monitor" >/dev/null 2>&1 || true
    hyprctl dispatch dpms on "$INTERNAL" >/dev/null 2>&1 || true

    wait_for_internal

    if internal_available; then
      if external_available; then
        configure_docked_open_workspaces "$current_ws"
      else
        move_main_workspaces "$INTERNAL" "$current_ws"
        restore_workspace "$current_ws"
      fi
      reload_waybar
    fi
    ;;
esac
