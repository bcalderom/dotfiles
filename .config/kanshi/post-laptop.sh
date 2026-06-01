#!/usr/bin/env bash

command -v hyprctl >/dev/null 2>&1 || exit 0

INTERNAL="eDP-1"

current_ws="$(hyprctl activeworkspace 2>/dev/null | awk '/^workspace ID/ { print $3; exit }')"

hyprctl keyword monitor "$INTERNAL,preferred,auto,1" >/dev/null 2>&1 || true
hyprctl dispatch dpms on "$INTERNAL" >/dev/null 2>&1 || true

i=0
while [ "$i" -lt 30 ]; do
  if hyprctl monitors 2>/dev/null | grep -q "^Monitor ${INTERNAL} "; then
    break
  fi
  sleep 0.1
  i=$((i + 1))
done

hyprctl dispatch moveworkspacetomonitor 1 "$INTERNAL" >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor 2 "$INTERNAL" >/dev/null 2>&1 || true

if [ -n "$current_ws" ]; then
  hyprctl dispatch moveworkspacetomonitor "$current_ws" "$INTERNAL" >/dev/null 2>&1 || true
  hyprctl dispatch workspace "$current_ws" >/dev/null 2>&1 || true
fi

~/.config/kanshi/audio-route.sh >/dev/null 2>&1 || true
