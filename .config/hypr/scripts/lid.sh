#!/usr/bin/env bash

INTERNAL="eDP-1"
EXTERNAL="DP-1"

command -v hyprctl >/dev/null 2>&1 || exit 0

if grep -q closed /proc/acpi/button/lid/*/state; then
  if hyprctl monitors | grep -q "^Monitor ${EXTERNAL} "; then
    hyprctl keyword monitor "$INTERNAL,disable"
    hyprctl dispatch moveworkspacetomonitor 1 "$EXTERNAL" >/dev/null 2>&1 || true
  fi
else
  hyprctl keyword monitor "$INTERNAL,preferred,auto,1"
fi
