#!/usr/bin/env bash

INTERNAL="eDP-1"
EXTERNAL="DP-1"
HDMI="HDMI-A-1"
STATE="${1:-}"
LID_STATE_PATH="${LID_STATE_PATH:-}"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-lid.lock"
ACTIVE_WORKSPACE_FILE="${HYPR_LID_ACTIVE_WORKSPACE_FILE:-${XDG_RUNTIME_DIR:-/tmp}/hypr-lid-active-workspace}"
RECOVERY_FILE="${HYPR_LID_RECOVERY_FILE:-${XDG_RUNTIME_DIR:-/tmp}/hypr-lid-recovery}"
BACKLIGHT_STATE_FILE="${HYPR_LID_BACKLIGHT_STATE_FILE:-${XDG_RUNTIME_DIR:-/tmp}/hypr-lid-backlight}"
BACKLIGHT_DEVICE="${HYPR_LID_BACKLIGHT_DEVICE:-intel_backlight}"
AUDIO_ROUTE_SCRIPT="${HYPR_LID_AUDIO_ROUTE_SCRIPT:-${HOME}/.config/kanshi/audio-route.sh}"
HYPRCTL_TIMEOUT="${HYPR_LID_HYPRCTL_TIMEOUT:-3s}"
RECOVERY_DELAY="${HYPR_LID_RECOVERY_DELAY:-2}"

log() { printf 'hypr-lid: %s\n' "$*" >&2; }

command -v hyprctl >/dev/null 2>&1 || exit 0

if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE" || exit 75
  flock -n 9 || exit 75
fi

hyprctl_run() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$HYPRCTL_TIMEOUT" hyprctl "$@"
  else
    hyprctl "$@"
  fi
}

hyprctl_quiet() { hyprctl_run "$@" >/dev/null 2>&1; }

lid_is_closed() {
  if [ -n "$LID_STATE_PATH" ]; then
    grep -q closed "$LID_STATE_PATH" 2>/dev/null
  else
    grep -q closed /proc/acpi/button/lid/*/state 2>/dev/null
  fi
}

if [ -z "$STATE" ]; then
  if lid_is_closed; then STATE="closed"; else STATE="open"; fi
fi

monitors_all() { hyprctl_run monitors all 2>/dev/null || hyprctl_run monitors 2>/dev/null || true; }
monitors_active() { hyprctl_run monitors 2>/dev/null || true; }
monitor_known() { monitors_all | grep -q "^Monitor $1 "; }
monitor_active() { monitors_active | grep -q "^Monitor $1 "; }
external_available() { monitor_known "$EXTERNAL"; }
hdmi_available() { monitor_known "$HDMI"; }
internal_available() { monitor_active "$INTERNAL"; }

wait_for_monitor() {
  local monitor="$1" i=0
  while [ "$i" -lt 30 ]; do
    monitor_active "$monitor" && return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

topology_key() {
  local external=0 internal=0 hdmi=0
  external_available && external=1
  internal_available && internal=1
  hdmi_available && hdmi=1
  printf '%s|external:%s|internal:%s|hdmi:%s' "$STATE" "$external" "$internal" "$hdmi"
}

reload_already_tried() { [ -f "$RECOVERY_FILE" ] && [ "$(cat "$RECOVERY_FILE" 2>/dev/null)" = "$1" ]; }

mark_reload_tried() {
  local tmp="${RECOVERY_FILE}.$$"
  printf '%s\n' "$1" > "$tmp" 2>/dev/null && mv "$tmp" "$RECOVERY_FILE" 2>/dev/null || true
}

enable_external() {
  if ! monitor_active "$EXTERNAL"; then
    hyprctl_quiet keyword monitor "$EXTERNAL,2560x1440@120.01,1920x0,1" || true
  fi
  wait_for_monitor "$EXTERNAL"
}

enable_internal_once() {
  if ! monitor_active "$INTERNAL"; then
    hyprctl_quiet keyword monitor "$INTERNAL,preferred,0x0,1" || true
  fi
  wait_for_monitor "$INTERNAL"
}

enable_internal() {
  local key="$1"
  enable_internal_once && return 0
  reload_already_tried "$key" && return 1
  mark_reload_tried "$key"
  log "internal output still inactive; trying one delayed Hyprland reload for $key"
  sleep "$RECOVERY_DELAY"
  hyprctl_quiet reload || return 1
  enable_internal_once
}

disable_hdmi() {
  monitor_active "$HDMI" || return 0
  hyprctl_quiet keyword monitor "$HDMI,disable" || true
}

route_audio() {
  [ -x "$AUDIO_ROUTE_SCRIPT" ] || return 0
  "$AUDIO_ROUTE_SCRIPT" >/dev/null 2>&1 || true
}

backlight_off() {
  local brightness tmp
  command -v brightnessctl >/dev/null 2>&1 || return 0
  brightness="$(brightnessctl -d "$BACKLIGHT_DEVICE" get 2>/dev/null || true)"
  case "$brightness" in ''|*[!0-9]*) return 0 ;; esac
  [ "$brightness" -gt 0 ] || return 0
  tmp="${BACKLIGHT_STATE_FILE}.$$"
  printf '%s\n' "$brightness" > "$tmp" && mv "$tmp" "$BACKLIGHT_STATE_FILE"
  brightnessctl -q -d "$BACKLIGHT_DEVICE" set 0 || log "failed to turn off $BACKLIGHT_DEVICE"
}

backlight_on() {
  local brightness
  command -v brightnessctl >/dev/null 2>&1 || return 0
  [ -f "$BACKLIGHT_STATE_FILE" ] || return 0
  brightness="$(cat "$BACKLIGHT_STATE_FILE" 2>/dev/null || true)"
  case "$brightness" in ''|*[!0-9]*) return 0 ;; esac
  if brightnessctl -q -d "$BACKLIGHT_DEVICE" set "$brightness"; then rm -f "$BACKLIGHT_STATE_FILE"; else log "failed to restore $BACKLIGHT_DEVICE"; fi
}

active_workspace() { hyprctl_run activeworkspace 2>/dev/null | awk '/^workspace ID/ { print $3; exit }'; }
recorded_workspace() { [ -f "$ACTIVE_WORKSPACE_FILE" ] && awk 'NR == 1 && $1 ~ /^[0-9]+$/ { print $1; exit }' "$ACTIVE_WORKSPACE_FILE" 2>/dev/null; }

workspace_ids() {
  hyprctl_run workspaces 2>/dev/null | awk '$1 == "workspace" && $2 == "ID" && $3 ~ /^[0-9]+$/ { print $3 }'
}

workspace_ids_with_windows() {
  hyprctl_run workspaces 2>/dev/null | awk '
    $1 == "workspace" && $2 == "ID" && $3 ~ /^[0-9]+$/ { workspace = $3 }
    $1 == "windows:" && $2 > 0 { print workspace }'
}

workspace_ids_on_monitor() {
  hyprctl_run workspaces 2>/dev/null | awk -v monitor="$1" '
    $1 == "workspace" && $2 == "ID" && $3 ~ /^[0-9]+$/ {
      workspace_monitor = $7; sub(/:$/, "", workspace_monitor)
      if (workspace_monitor == monitor) print $3
    }'
}

workspace_ids_on_monitor_with_windows() {
  hyprctl_run workspaces 2>/dev/null | awk -v monitor="$1" '
    $1 == "workspace" && $2 == "ID" && $3 ~ /^[0-9]+$/ {
      workspace = $3; workspace_monitor = $7; sub(/:$/, "", workspace_monitor)
      candidate = workspace_monitor == monitor
    }
    candidate && $1 == "windows:" && $2 > 0 { print workspace; candidate = 0 }'
}

workspace_monitor() {
  hyprctl_run workspaces 2>/dev/null | awk -v workspace="$1" '
    $1 == "workspace" && $2 == "ID" && $3 == workspace { monitor = $7; sub(/:$/, "", monitor); print monitor; exit }'
}

workspace_on_monitor() {
  [ -n "$1" ] || return 1
  [ -n "$2" ] || return 1
  [ "$(workspace_monitor "$1")" = "$2" ]
}

next_workspace_after_monitor() { workspace_ids_on_monitor "$1" | awk 'max < $1 { max = $1 } END { print max + 1 }'; }

next_docked_open_workspace() {
  { printf '%s\n' 1 2; workspace_ids_on_monitor_with_windows "$EXTERNAL"; } |
    awk 'max < $1 { max = $1 } END { print max + 1 }'
}

movable_workspace_ids() {
  { [ -n "$1" ] && printf '%s\n' "$1"; workspace_ids_with_windows; } |
    awk '$1 ~ /^[0-9]+$/ && !seen[$1]++ { print $1 }'
}

movable_external_workspace_ids() {
  { workspace_ids_on_monitor_with_windows "$EXTERNAL"; [ "$2" -eq 1 ] && printf '%s\n' "$1"; } |
    awk '$1 ~ /^[0-9]+$/ && !seen[$1]++ { print $1 }'
}

bind_nonpersistent_workspace() { hyprctl_quiet keyword workspace "$1,monitor:$2,persistent:false" || true; }
move_workspace() { hyprctl_quiet dispatch moveworkspacetomonitor "$1" "$2" || true; }
restore_workspace() { [ -n "$1" ] && hyprctl_quiet dispatch workspace "$1" || true; }

demote_retired_workspaces() {
  local protected_file="$1" workspace monitor
  workspace_ids | while IFS= read -r workspace; do
    grep -qx "$workspace" "$protected_file" && continue
    monitor="$(workspace_monitor "$workspace")"
    [ -n "$monitor" ] && bind_nonpersistent_workspace "$workspace" "$monitor"
  done
}

move_main_workspaces() {
  local target="$1" current_ws="${2:-}" protected_file
  protected_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/hypr-lid-protected.XXXXXX")" || return 1
  movable_workspace_ids "$current_ws" > "$protected_file"
  bind_nonpersistent_workspace 1 "$target"
  bind_nonpersistent_workspace 2 "$target"
  while IFS= read -r workspace; do bind_nonpersistent_workspace "$workspace" "$target"; done < "$protected_file"
  demote_retired_workspaces "$protected_file"
  while IFS= read -r workspace; do move_workspace "$workspace" "$target"; done < "$protected_file"
  rm -f "$protected_file"
}

configure_docked_open_workspaces() {
  local current_ws="${1:-}" internal_ws="${2:-}" restore_current="${3:-0}" protected_file external_file
  [ -n "$internal_ws" ] || internal_ws="$(next_workspace_after_monitor "$EXTERNAL")"
  protected_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/hypr-lid-protected.XXXXXX")" || return 1
  external_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/hypr-lid-external.XXXXXX")" || { rm -f "$protected_file"; return 1; }

  movable_external_workspace_ids "$current_ws" "$restore_current" > "$external_file"
  { cat "$external_file"; printf '%s\n' "$internal_ws"; } | awk '$1 ~ /^[0-9]+$/ && !seen[$1]++ { print $1 }' > "$protected_file"
  bind_nonpersistent_workspace 1 "$EXTERNAL"
  bind_nonpersistent_workspace 2 "$EXTERNAL"
  while IFS= read -r workspace; do bind_nonpersistent_workspace "$workspace" "$EXTERNAL"; done < "$external_file"
  bind_nonpersistent_workspace "$internal_ws" "$INTERNAL"
  demote_retired_workspaces "$protected_file"
  while IFS= read -r workspace; do move_workspace "$workspace" "$EXTERNAL"; done < "$external_file"
  restore_workspace "$internal_ws"
  move_workspace "$internal_ws" "$INTERNAL"
  if [ "$restore_current" -eq 1 ] || [ "$current_ws" = "$internal_ws" ]; then restore_workspace "$current_ws"; fi
  rm -f "$protected_file" "$external_file"
}

transition_status=0

case "$STATE" in
  closed|close)
    current_ws="$(active_workspace)"
    i=0
    while [ "$i" -lt 30 ]; do external_available && break; sleep 0.1; i=$((i + 1)); done
    if external_available; then
      if enable_external; then
        enable_internal "$(topology_key)" || transition_status=1
        disable_hdmi
        move_main_workspaces "$EXTERNAL" "$current_ws"
        restore_workspace "$current_ws"
        backlight_off
        route_audio
      else
        transition_status=1
      fi
    fi
    ;;
  open)
    current_ws="$(active_workspace)"
    current_ws_on_external=0
    workspace_on_monitor "$current_ws" "$EXTERNAL" && current_ws_on_external=1
    internal_ws="$(next_docked_open_workspace)"

    if external_available; then
      enable_external || exit 1
      disable_hdmi
      enable_internal "$(topology_key)" || exit 1
    elif hdmi_available; then
      enable_internal "$(topology_key)" || exit 1
      hyprctl_quiet keyword monitor "$HDMI,1920x1080@60,0x0,1,mirror,$INTERNAL" || true
    else
      enable_internal "$(topology_key)" || exit 1
    fi

    if external_available; then
      configure_docked_open_workspaces "$current_ws" "$internal_ws" "$current_ws_on_external"
    else
      restore_ws="$(recorded_workspace)"
      [ -n "$restore_ws" ] || restore_ws="$current_ws"
      move_main_workspaces "$INTERNAL" "$restore_ws"
      restore_workspace "$restore_ws"
    fi
    backlight_on
    route_audio
    ;;
  *)
    exit 0
    ;;
esac

exit "$transition_status"
