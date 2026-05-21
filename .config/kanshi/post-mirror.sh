#!/usr/bin/env bash

command -v hyprctl >/dev/null 2>&1 || exit 0

hyprctl keyword monitor "eDP-1,preferred,0x0,1" >/dev/null 2>&1 || true
hyprctl keyword monitor "HDMI-A-1,1920x1080@60,0x0,1,mirror,eDP-1" >/dev/null 2>&1 || true

~/.config/kanshi/audio-route.sh >/dev/null 2>&1 || true
