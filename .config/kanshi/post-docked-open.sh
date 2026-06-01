#!/usr/bin/env bash

command -v hyprctl >/dev/null 2>&1 || exit 0

reload_waybar() {
  command -v pkill >/dev/null 2>&1 || return 0
  pkill -SIGUSR2 -x waybar >/dev/null 2>&1 || true
}

INTERNAL="eDP-1"
EXTERNAL="DP-1"

current_ws="$(hyprctl activeworkspace 2>/dev/null | awk '/^workspace ID/ { print $3; exit }')"

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

hyprctl keyword workspace "1,monitor:$EXTERNAL" >/dev/null 2>&1 || true
hyprctl keyword workspace "2,monitor:$INTERNAL" >/dev/null 2>&1 || true

hyprctl dispatch moveworkspacetomonitor 1 "$EXTERNAL" >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor 2 "$INTERNAL" >/dev/null 2>&1 || true

case "$current_ws" in
  1)
    hyprctl dispatch workspace 2 >/dev/null 2>&1 || true
    hyprctl dispatch workspace 1 >/dev/null 2>&1 || true
    ;;
  2)
    hyprctl dispatch workspace 2 >/dev/null 2>&1 || true
    ;;
  *)
    hyprctl dispatch workspace 2 >/dev/null 2>&1 || true
    ;;
esac

~/.config/kanshi/audio-route.sh >/dev/null 2>&1 || true
reload_waybar
