#!/usr/bin/env bash

command -v hyprctl >/dev/null 2>&1 || exit 0

i=0
while [ "$i" -lt 30 ]; do
  if hyprctl monitors 2>/dev/null | grep -q "^Monitor eDP-1 "; then
    break
  fi
  sleep 0.1
  i=$((i + 1))
done

hyprctl dispatch moveworkspacetomonitor 1 eDP-1 >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor 2 eDP-1 >/dev/null 2>&1 || true
