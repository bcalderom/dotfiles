#!/usr/bin/env bash

INTERNAL="eDP-1"

if grep -q closed /proc/acpi/button/lid/*/state; then
  hyprctl keyword monitor "$INTERNAL,disable"
else
  hyprctl keyword monitor "$INTERNAL,preferred,auto,1"
fi
