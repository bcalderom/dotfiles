#!/usr/bin/env bash
set -euo pipefail

LID_STATE_PATH="${LID_STATE_PATH:-/proc/acpi/button/lid/LID0/state}"
LID_HANDLER="${LID_HANDLER:-${HOME}/.config/hypr/scripts/lid.sh}"
LID_POLL_INTERVAL="${LID_POLL_INTERVAL:-1}"
LID_SETTLE_DELAY="${LID_SETTLE_DELAY:-0.5}"
LID_STABLE_SAMPLES="${LID_STABLE_SAMPLES:-4}"
LID_RECONCILE_INTERVAL="${LID_RECONCILE_INTERVAL:-5}"
LID_WATCH_ITERATIONS="${LID_WATCH_ITERATIONS:-}"
LID_FAILURE_INITIAL_BACKOFF="${LID_FAILURE_INITIAL_BACKOFF:-2}"
LID_FAILURE_MAX_BACKOFF="${LID_FAILURE_MAX_BACKOFF:-60}"
LID_INTERNAL_OUTPUT="${LID_INTERNAL_OUTPUT:-eDP-1}"
LID_EXTERNAL_OUTPUT="${LID_EXTERNAL_OUTPUT:-DP-1}"
LID_HDMI_OUTPUT="${LID_HDMI_OUTPUT:-HDMI-A-1}"
ACTIVE_WORKSPACE_FILE="${HYPR_LID_ACTIVE_WORKSPACE_FILE:-${XDG_RUNTIME_DIR:-/tmp}/hypr-lid-active-workspace}"

log() { printf 'hypr-lid: %s\n' "$*" >&2; }
now_epoch() { date +%s; }
active_workspace() { hyprctl activeworkspace 2>/dev/null | awk '/^workspace ID/ { print $3; exit }'; }

record_active_workspace() {
  local workspace tmp
  workspace="$(active_workspace)"
  [ -n "$workspace" ] || return 0
  tmp="${ACTIVE_WORKSPACE_FILE}.$$"
  printf '%s\n' "$workspace" > "$tmp" && mv "$tmp" "$ACTIVE_WORKSPACE_FILE"
}

ensure_hyprland_env() {
  local instance
  command -v hyprctl >/dev/null 2>&1 || return 1
  if hyprctl monitors >/dev/null 2>&1; then return 0; fi
  instance="$(env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY hyprctl instances 2>/dev/null | awk '
    /^instance / { signature = $2; sub(/:$/, "", signature) }
    /^[[:space:]]*wl socket:/ && signature != "" { print signature " " $3; exit }')"
  [ -n "$instance" ] || return 1
  HYPRLAND_INSTANCE_SIGNATURE="${instance%% *}"
  WAYLAND_DISPLAY="${instance#* }"
  export HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
  hyprctl monitors >/dev/null 2>&1
}

read_lid_state() {
  if grep -q closed "$LID_STATE_PATH" 2>/dev/null; then
    printf 'closed'
  elif grep -q open "$LID_STATE_PATH" 2>/dev/null; then
    printf 'open'
  else
    printf 'unknown'
  fi
}

run_handler() {
  local lid_state="${1:-}"
  case "$lid_state" in open|closed) ;; *) return 0 ;; esac
  ensure_hyprland_env || return 0
  [ -x "$LID_HANDLER" ] || return 0
  "$LID_HANDLER" "$lid_state"
}

read_monitor_state() {
  local active_monitors all_monitors external=0 internal=0 hdmi=0
  if ! ensure_hyprland_env; then printf 'external:unknown|internal:unknown'; return 0; fi
  active_monitors="$(hyprctl monitors 2>/dev/null || true)"
  all_monitors="$(hyprctl monitors all 2>/dev/null || printf '%s' "$active_monitors")"
  grep -q "^Monitor ${LID_EXTERNAL_OUTPUT} " <<< "$all_monitors" && external=1
  grep -q "^Monitor ${LID_INTERNAL_OUTPUT} " <<< "$active_monitors" && internal=1
  grep -q "^Monitor ${LID_HDMI_OUTPUT} " <<< "$all_monitors" && hdmi=1
  printf 'external:%s|internal:%s|hdmi:%s' "$external" "$internal" "$hdmi"
}

read_watch_state() {
  local lid_state monitor_state
  lid_state="$(read_lid_state)"
  [ "$lid_state" = "unknown" ] && { printf 'unknown'; return 0; }
  monitor_state="$(read_monitor_state)"
  case "$monitor_state" in *unknown*) printf 'unknown' ;; *) printf '%s|%s' "$lid_state" "$monitor_state" ;; esac
}

workspace_rule_mismatch() {
  local workspace="$1" monitor="$2" rules compact
  ensure_hyprland_env || return 1
  rules="$(hyprctl -j workspacerules 2>/dev/null || true)"
  [ -n "$rules" ] || return 1
  compact="$(printf '%s' "$rules" | tr -d '[:space:]')"
  case "$compact" in *"\"workspaceString\":\"${workspace}\",\"monitor\":\"${monitor}\""*) return 1 ;; *) return 0 ;; esac
}

workspace_location_mismatch() {
  local workspace="$1" monitor="$2" workspaces
  ensure_hyprland_env || return 1
  workspaces="$(hyprctl workspaces 2>/dev/null || true)"
  [ -n "$workspaces" ] || return 1
  grep -q "^workspace ID ${workspace} (${workspace}) on monitor " <<< "$workspaces" || return 1
  grep -q "^workspace ID ${workspace} (${workspace}) on monitor ${monitor}:" <<< "$workspaces" && return 1
  return 0
}

next_docked_open_workspace() {
  { printf '%s\n' 1 2; hyprctl workspaces 2>/dev/null | awk -v monitor="$LID_EXTERNAL_OUTPUT" '
    $1 == "workspace" && $2 == "ID" && $3 ~ /^[0-9]+$/ { workspace = $3; workspace_monitor = $7; sub(/:$/, "", workspace_monitor); candidate = workspace_monitor == monitor }
    candidate && $1 == "windows:" && $2 > 0 { print workspace; candidate = 0 }'; } |
    awk 'max < $1 { max = $1 } END { print max + 1 }'
}

monitor_workspace_mismatch() {
  local active
  active="$(hyprctl monitors 2>/dev/null | awk -v monitor="$1" '
    $1 == "Monitor" { current = $2 }
    current == monitor && $1 == "active" && $2 == "workspace:" { print $3; exit }')"
  [ "$active" = "$2" ] && return 1
  return 0
}

workspace_mismatch() {
  workspace_rule_mismatch "$1" "$2" && return 0
  workspace_location_mismatch "$1" "$2" && return 0
  return 1
}

needs_reconcile() {
  local internal_workspace
  case "$1" in
    closed\|external:1\|internal:*)
      case "$1" in *\|internal:0*) return 0 ;; esac
      workspace_mismatch 1 "$LID_EXTERNAL_OUTPUT" && return 0
      workspace_mismatch 2 "$LID_EXTERNAL_OUTPUT" && return 0
      ;;
    open\|external:1\|internal:*)
      internal_workspace="$(next_docked_open_workspace)"
      case "$1" in *\|internal:0*) return 0 ;; esac
      workspace_mismatch 1 "$LID_EXTERNAL_OUTPUT" && return 0
      workspace_mismatch 2 "$LID_EXTERNAL_OUTPUT" && return 0
      workspace_rule_mismatch "$internal_workspace" "$LID_INTERNAL_OUTPUT" && return 0
      monitor_workspace_mismatch "$LID_INTERNAL_OUTPUT" "$internal_workspace" && return 0
      ;;
    open\|external:0\|internal:*\|hdmi:1)
      case "$1" in *\|internal:0*) return 0 ;; esac
      workspace_mismatch 1 "$LID_INTERNAL_OUTPUT" && return 0
      workspace_mismatch 2 "$LID_INTERNAL_OUTPUT" && return 0
      ;;
    open\|external:0\|internal:*\|hdmi:0)
      case "$1" in *\|internal:0*) return 0 ;; esac
      workspace_mismatch 1 "$LID_INTERNAL_OUTPUT" && return 0
      workspace_mismatch 2 "$LID_INTERNAL_OUTPUT" && return 0
      ;;
  esac
  return 1
}

stable_state() {
  local expected="$1" sample=1 current
  while [ "$sample" -lt "$LID_STABLE_SAMPLES" ]; do
    sleep "$LID_SETTLE_DELAY"
    current="$(read_watch_state)"
    [ "$current" = "$expected" ] || return 1
    sample=$((sample + 1))
  done
  printf '%s' "$expected"
}

defer_failed_state() {
  [ "$1" = "$failed_state" ] || return 1
  [ "$(now_epoch)" -lt "$next_retry_at" ]
}

clear_failure() {
  failed_state=""
  failure_delay="$LID_FAILURE_INITIAL_BACKOFF"
  next_retry_at=0
}

mark_failure() {
  local state="$1" delay
  if [ "$state" != "$failed_state" ]; then
    failed_state="$state"
    failure_delay="$LID_FAILURE_INITIAL_BACKOFF"
  else
    delay=$((failure_delay * 2))
    if [ "$delay" -gt "$LID_FAILURE_MAX_BACKOFF" ]; then delay="$LID_FAILURE_MAX_BACKOFF"; fi
    failure_delay="$delay"
  fi
  next_retry_at=$(($(now_epoch) + failure_delay))
  log "handler failed for $state; retrying in ${failure_delay}s"
}

last_state=""
failed_state=""
failure_delay="$LID_FAILURE_INITIAL_BACKOFF"
next_retry_at=0
iterations=0
reconcile_iterations=0

while :; do
  state="$(read_watch_state)"
  check_reconcile=0

  if [ "$state" != "unknown" ]; then
    reconcile_iterations=$((reconcile_iterations + 1))
    if [ "$reconcile_iterations" -ge "$LID_RECONCILE_INTERVAL" ]; then
      reconcile_iterations=0
      check_reconcile=1
    fi
  fi

  if [ "$state" != "unknown" ] && { [ "$state" != "$last_state" ] || { [ "$check_reconcile" -eq 1 ] && needs_reconcile "$state"; }; }; then
    if ! state="$(stable_state "$state")"; then state="unknown"; fi

    if [ "$state" != "unknown" ] && { [ "$state" != "$last_state" ] || needs_reconcile "$state"; }; then
      if defer_failed_state "$state"; then
        :
      else
        log "handling $state"
        if run_handler "${state%%|*}"; then
          state="$(read_watch_state)"
          if [ "$state" != "unknown" ] && stable_state "$state" >/dev/null && ! needs_reconcile "$state"; then
            last_state="$state"
            clear_failure
          else
            mark_failure "$state"
          fi
        else
          mark_failure "$state"
        fi
      fi
    fi
  fi

  if [ "$state" != "unknown" ] && [ "$state" = "$last_state" ]; then record_active_workspace; fi

  if [ -n "$LID_WATCH_ITERATIONS" ]; then
    iterations=$((iterations + 1))
    [ "$iterations" -ge "$LID_WATCH_ITERATIONS" ] && exit 0
  fi

  sleep "$LID_POLL_INTERVAL"
done
