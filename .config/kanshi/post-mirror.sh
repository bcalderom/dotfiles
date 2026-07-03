#!/usr/bin/env bash

command -v hyprctl >/dev/null 2>&1 || exit 0

INTERNAL="eDP-1"
HDMI="HDMI-A-1"

current_ws="$(hyprctl activeworkspace 2>/dev/null | awk '/^workspace ID/ { print $3; exit }')"

hyprctl keyword monitor "$INTERNAL,preferred,0x0,1" >/dev/null 2>&1 || true
hyprctl keyword monitor "$HDMI,1920x1080@60,0x0,1,mirror,$INTERNAL" >/dev/null 2>&1 || true
hyprctl dispatch dpms on "$INTERNAL" >/dev/null 2>&1 || true

hyprctl keyword workspace "1,monitor:$INTERNAL" >/dev/null 2>&1 || true
hyprctl keyword workspace "2,monitor:$INTERNAL" >/dev/null 2>&1 || true
hyprctl keyword workspace "3,monitor:$INTERNAL,persistent:true" >/dev/null 2>&1 || true

hyprctl dispatch moveworkspacetomonitor 1 "$INTERNAL" >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor 2 "$INTERNAL" >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor 3 "$INTERNAL" >/dev/null 2>&1 || true

if [ -n "$current_ws" ]; then
  hyprctl dispatch moveworkspacetomonitor "$current_ws" "$INTERNAL" >/dev/null 2>&1 || true
  hyprctl dispatch workspace "$current_ws" >/dev/null 2>&1 || true
fi

~/.config/kanshi/audio-route.sh >/dev/null 2>&1 || true
