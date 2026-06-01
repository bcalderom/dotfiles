#!/usr/bin/env bash

INTERNAL="eDP-1"
EXTERNAL="DP-1"
STATE="${1:-}"

command -v hyprctl >/dev/null 2>&1 || exit 0

if [ -z "$STATE" ]; then
  if grep -q closed /proc/acpi/button/lid/*/state 2>/dev/null; then
    STATE="closed"
  else
    STATE="open"
  fi
fi

external_available() {
  hyprctl monitors 2>/dev/null | grep -q "^Monitor ${EXTERNAL} "
}

switch_docked_profile() {
  command -v kanshictl >/dev/null 2>&1 || return 1

  kanshictl switch docked_dp_hdmi >/dev/null 2>&1 || \
    kanshictl switch docked_dp_only >/dev/null 2>&1
}

switch_laptop_profile() {
  command -v kanshictl >/dev/null 2>&1 || return 1

  kanshictl switch laptop >/dev/null 2>&1
}

switch_docked_open_profile() {
  command -v kanshictl >/dev/null 2>&1 || return 1

  kanshictl switch docked_open_dp_hdmi >/dev/null 2>&1 || \
    kanshictl switch docked_open_dp_only >/dev/null 2>&1
}

internal_available() {
  hyprctl monitors 2>/dev/null | grep -q "^Monitor ${INTERNAL} "
}

active_workspace() {
  hyprctl activeworkspace 2>/dev/null | awk '/^workspace ID/ { print $3; exit }'
}

case "$STATE" in
  closed|close)
    i=0
    while [ "$i" -lt 30 ]; do
      if external_available; then
        break
      fi
      sleep 0.1
      i=$((i + 1))
    done

    if external_available; then
      switch_docked_profile || true

      current_ws="$(active_workspace)"

      hyprctl dispatch moveworkspacetomonitor 1 "$EXTERNAL" >/dev/null 2>&1 || true
      hyprctl dispatch moveworkspacetomonitor 2 "$EXTERNAL" >/dev/null 2>&1 || true

      if [ -n "$current_ws" ]; then
        hyprctl dispatch moveworkspacetomonitor "$current_ws" "$EXTERNAL" >/dev/null 2>&1 || true
        hyprctl dispatch workspace "$current_ws" >/dev/null 2>&1 || true
      fi

      hyprctl keyword monitor "$INTERNAL,disable" >/dev/null 2>&1 || true
    fi
    ;;
  open)
    current_ws="$(active_workspace)"

    if external_available; then
      switch_docked_open_profile || true
    else
      switch_laptop_profile || true
    fi

    hyprctl keyword monitor "$INTERNAL,preferred,auto,1" >/dev/null 2>&1 || true
    hyprctl dispatch dpms on "$INTERNAL" >/dev/null 2>&1 || true

    i=0
    while [ "$i" -lt 30 ]; do
      if internal_available; then
        break
      fi
      sleep 0.1
      i=$((i + 1))
    done

    if internal_available; then
      if external_available; then
        hyprctl dispatch moveworkspacetomonitor 1 "$EXTERNAL" >/dev/null 2>&1 || true
        hyprctl dispatch moveworkspacetomonitor 2 "$INTERNAL" >/dev/null 2>&1 || true

        case "$current_ws" in
          1|2)
            hyprctl dispatch workspace "$current_ws" >/dev/null 2>&1 || true
            ;;
          *)
            hyprctl dispatch workspace 2 >/dev/null 2>&1 || true
            ;;
        esac
      else
        hyprctl dispatch moveworkspacetomonitor 1 "$INTERNAL" >/dev/null 2>&1 || true
        hyprctl dispatch moveworkspacetomonitor 2 "$INTERNAL" >/dev/null 2>&1 || true

        if [ -n "$current_ws" ]; then
          hyprctl dispatch moveworkspacetomonitor "$current_ws" "$INTERNAL" >/dev/null 2>&1 || true
          hyprctl dispatch workspace "$current_ws" >/dev/null 2>&1 || true
        fi
      fi
    fi
    ;;
esac
