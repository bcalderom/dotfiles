#!/usr/bin/env bash

command -v hyprctl >/dev/null 2>&1 || exit 0

reload_waybar() {
  command -v pgrep >/dev/null 2>&1 || return 0
  pgrep -x waybar >/dev/null 2>&1 || return 0
  hyprctl dispatch exec "bash -lc 'pkill -x waybar >/dev/null 2>&1 || true; waybar'" >/dev/null 2>&1 || true
}

INTERNAL="eDP-1"
EXTERNAL="DP-1"

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

next_workspace_after_monitor() {
  workspace_ids_on_monitor "$1" | awk 'max < $1 { max = $1 } END { print max + 1 }'
}

next_docked_open_workspace() {
  {
    printf '%s\n' 1 2
    workspace_ids_on_monitor_with_windows "$EXTERNAL"
  } | awk 'max < $1 { max = $1 } END { print max + 1 }'
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

current_ws="$(hyprctl activeworkspace 2>/dev/null | awk '/^workspace ID/ { print $3; exit }')"
current_ws_on_external=0
if workspace_on_monitor "$current_ws" "$EXTERNAL"; then
  current_ws_on_external=1
fi
internal_ws="$(next_docked_open_workspace)"

hyprctl keyword monitor "$INTERNAL,preferred,0x0,1" >/dev/null 2>&1 || true
hyprctl keyword monitor "$EXTERNAL,2560x1440@120.01,1920x0,1" >/dev/null 2>&1 || true
hyprctl dispatch dpms on "$INTERNAL" >/dev/null 2>&1 || true

i=0
while [ "$i" -lt 30 ]; do
  if hyprctl monitors 2>/dev/null | grep -q "^Monitor ${INTERNAL} " && \
    hyprctl monitors 2>/dev/null | grep -q "^Monitor ${EXTERNAL} "; then
    break
  fi
  sleep 0.1
  i=$((i + 1))
done

workspace_ids_on_monitor "$EXTERNAL" | while IFS= read -r workspace; do
  hyprctl keyword workspace "$workspace,monitor:$EXTERNAL,persistent:false" >/dev/null 2>&1 || true
done
hyprctl keyword workspace "1,monitor:$EXTERNAL" >/dev/null 2>&1 || true
hyprctl keyword workspace "2,monitor:$EXTERNAL" >/dev/null 2>&1 || true
hyprctl keyword workspace "$internal_ws,monitor:$INTERNAL,persistent:false" >/dev/null 2>&1 || true

hyprctl dispatch moveworkspacetomonitor 1 "$EXTERNAL" >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor 2 "$EXTERNAL" >/dev/null 2>&1 || true
hyprctl dispatch workspace "$internal_ws" >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor "$internal_ws" "$INTERNAL" >/dev/null 2>&1 || true

if [ "$current_ws_on_external" -eq 1 ] || [ "$current_ws" = "$internal_ws" ]; then
  hyprctl dispatch workspace "$current_ws" >/dev/null 2>&1 || true
fi

~/.config/kanshi/audio-route.sh >/dev/null 2>&1 || true
reload_waybar
