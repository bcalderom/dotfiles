#!/usr/bin/env bash

command -v hyprctl >/dev/null 2>&1 || exit 0

reload_waybar() {
  command -v pgrep >/dev/null 2>&1 || return 0
  pgrep -x waybar >/dev/null 2>&1 || return 0
  hyprctl dispatch exec "bash -lc 'pkill -x waybar >/dev/null 2>&1 || true; waybar'" >/dev/null 2>&1 || true
}

workspace_ids() {
  hyprctl workspaces 2>/dev/null | awk '$1 == "workspace" && $2 == "ID" && $3 ~ /^[0-9]+$/ { print $3 }'
}

i=0
while [ "$i" -lt 30 ]; do
  if hyprctl monitors 2>/dev/null | grep -q "^Monitor DP-1 "; then
    break
  fi
  sleep 0.1
  i=$((i + 1))
done

current_ws="$(hyprctl activeworkspace 2>/dev/null | awk '/^workspace ID/ { print $3; exit }')"

workspace_ids | while IFS= read -r workspace; do
  hyprctl keyword workspace "$workspace,monitor:DP-1,persistent:false" >/dev/null 2>&1 || true
  hyprctl dispatch moveworkspacetomonitor "$workspace" DP-1 >/dev/null 2>&1 || true
done

hyprctl keyword workspace "1,monitor:DP-1" >/dev/null 2>&1 || true
hyprctl keyword workspace "2,monitor:DP-1" >/dev/null 2>&1 || true
hyprctl keyword workspace "3,monitor:DP-1,persistent:false" >/dev/null 2>&1 || true

hyprctl dispatch moveworkspacetomonitor 1 DP-1 >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor 2 DP-1 >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor 3 DP-1 >/dev/null 2>&1 || true

if [ -n "$current_ws" ]; then
  hyprctl dispatch moveworkspacetomonitor "$current_ws" DP-1 >/dev/null 2>&1 || true
  hyprctl dispatch workspace "$current_ws" >/dev/null 2>&1 || true
fi

~/.config/kanshi/audio-route.sh >/dev/null 2>&1 || true
reload_waybar
