#!/usr/bin/env bash

command -v hyprctl >/dev/null 2>&1 || exit 0

INTERNAL="eDP-1"
HDMI="HDMI-A-1"
ACTIVE_WORKSPACE_FILE="${HYPR_LID_ACTIVE_WORKSPACE_FILE:-${XDG_RUNTIME_DIR:-/tmp}/hypr-lid-active-workspace}"

workspace_ids() {
  hyprctl workspaces 2>/dev/null | awk '$1 == "workspace" && $2 == "ID" && $3 ~ /^[0-9]+$/ { print $3 }'
}

recorded_workspace() {
  [ -f "$ACTIVE_WORKSPACE_FILE" ] || return 0
  awk 'NR == 1 && $1 ~ /^[0-9]+$/ { print $1; exit }' "$ACTIVE_WORKSPACE_FILE" 2>/dev/null
}

current_ws="$(hyprctl activeworkspace 2>/dev/null | awk '/^workspace ID/ { print $3; exit }')"
restore_ws="$(recorded_workspace)"
[ -n "$restore_ws" ] || restore_ws="$current_ws"

hyprctl keyword monitor "$INTERNAL,preferred,0x0,1" >/dev/null 2>&1 || true
hyprctl keyword monitor "$HDMI,1920x1080@60,0x0,1,mirror,$INTERNAL" >/dev/null 2>&1 || true
hyprctl dispatch dpms on "$INTERNAL" >/dev/null 2>&1 || true

workspace_ids | while IFS= read -r workspace; do
  hyprctl keyword workspace "$workspace,monitor:$INTERNAL,persistent:false" >/dev/null 2>&1 || true
  hyprctl dispatch moveworkspacetomonitor "$workspace" "$INTERNAL" >/dev/null 2>&1 || true
done

hyprctl keyword workspace "1,monitor:$INTERNAL" >/dev/null 2>&1 || true
hyprctl keyword workspace "2,monitor:$INTERNAL" >/dev/null 2>&1 || true
hyprctl keyword workspace "3,monitor:$INTERNAL,persistent:false" >/dev/null 2>&1 || true

hyprctl dispatch moveworkspacetomonitor 1 "$INTERNAL" >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor 2 "$INTERNAL" >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor 3 "$INTERNAL" >/dev/null 2>&1 || true

if [ -n "$restore_ws" ]; then
  hyprctl dispatch moveworkspacetomonitor "$restore_ws" "$INTERNAL" >/dev/null 2>&1 || true
  hyprctl dispatch workspace "$restore_ws" >/dev/null 2>&1 || true
fi

~/.config/kanshi/audio-route.sh >/dev/null 2>&1 || true
