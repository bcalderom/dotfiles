#!/usr/bin/env bash
set -euo pipefail

LID_STATE_PATH="${LID_STATE_PATH:-/proc/acpi/button/lid/LID0/state}"
LID_HANDLER="${LID_HANDLER:-${HOME}/.config/hypr/scripts/lid.sh}"
LID_POLL_INTERVAL="${LID_POLL_INTERVAL:-1}"
LID_SETTLE_DELAY="${LID_SETTLE_DELAY:-0.5}"
LID_RECONCILE_INTERVAL="${LID_RECONCILE_INTERVAL:-5}"
LID_WATCH_ITERATIONS="${LID_WATCH_ITERATIONS:-}"
LID_INTERNAL_OUTPUT="${LID_INTERNAL_OUTPUT:-eDP-1}"
LID_EXTERNAL_OUTPUT="${LID_EXTERNAL_OUTPUT:-DP-1}"

read_lid_state() {
  if grep -q closed "${LID_STATE_PATH}" 2>/dev/null; then
    printf 'closed'
  elif grep -q open "${LID_STATE_PATH}" 2>/dev/null; then
    printf 'open'
  else
    printf 'unknown'
  fi
}

run_handler() {
  [ -x "${LID_HANDLER}" ] || return 0
  "${LID_HANDLER}" >/dev/null 2>&1 || true
}

read_monitor_state() {
  local monitors external internal

  if ! command -v hyprctl >/dev/null 2>&1; then
    printf 'external:unknown|internal:unknown'
    return 0
  fi

  monitors="$(hyprctl monitors 2>/dev/null || true)"

  if grep -q "^Monitor ${LID_EXTERNAL_OUTPUT} " <<< "${monitors}"; then
    external=1
  else
    external=0
  fi

  if grep -q "^Monitor ${LID_INTERNAL_OUTPUT} " <<< "${monitors}"; then
    internal=1
  else
    internal=0
  fi

  printf 'external:%s|internal:%s' "${external}" "${internal}"
}

read_watch_state() {
  local lid_state

  lid_state="$(read_lid_state)"
  if [ "${lid_state}" = "unknown" ]; then
    printf 'unknown'
    return 0
  fi

  printf '%s|%s' "${lid_state}" "$(read_monitor_state)"
}

profile_mismatch() {
  local expected_prefix profile

  expected_prefix="$1"

  command -v kanshictl >/dev/null 2>&1 || return 1
  profile="$(kanshictl status 2>/dev/null | awk -F': ' '/^Current profile:/ { print $2; exit }')"
  [ -n "${profile}" ] || return 1

  case "${profile}" in
    "${expected_prefix}"*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

workspace_rule_mismatch() {
  local workspace monitor rules compact

  workspace="$1"
  monitor="$2"

  rules="$(hyprctl -j workspacerules 2>/dev/null || true)"
  [ -n "${rules}" ] || return 1
  compact="$(printf '%s' "${rules}" | tr -d '[:space:]')"

  case "${compact}" in
    *"\"workspaceString\":\"${workspace}\",\"monitor\":\"${monitor}\""*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

workspace_location_mismatch() {
  local workspace monitor workspaces

  workspace="$1"
  monitor="$2"

  workspaces="$(hyprctl workspaces 2>/dev/null || true)"
  [ -n "${workspaces}" ] || return 1

  if ! grep -q "^workspace ID ${workspace} (${workspace}) on monitor " <<< "${workspaces}"; then
    return 1
  fi

  if grep -q "^workspace ID ${workspace} (${workspace}) on monitor ${monitor}:" <<< "${workspaces}"; then
    return 1
  fi

  return 0
}

workspace_mismatch() {
  local workspace monitor

  workspace="$1"
  monitor="$2"

  workspace_rule_mismatch "${workspace}" "${monitor}" && return 0
  workspace_location_mismatch "${workspace}" "${monitor}" && return 0

  return 1
}

needs_reconcile() {
  case "$1" in
    closed\|external:1\|internal:*)
      case "$1" in
        *\|internal:1)
          return 0
          ;;
      esac
      profile_mismatch docked_dp_ && return 0
      workspace_mismatch 1 "${LID_EXTERNAL_OUTPUT}" && return 0
      workspace_mismatch 2 "${LID_EXTERNAL_OUTPUT}" && return 0
      ;;
    open\|external:1\|internal:*)
      case "$1" in
        *\|internal:0)
          return 0
          ;;
      esac
      profile_mismatch docked_open_dp_ && return 0
      workspace_mismatch 1 "${LID_EXTERNAL_OUTPUT}" && return 0
      workspace_mismatch 2 "${LID_INTERNAL_OUTPUT}" && return 0
      ;;
    open\|external:0\|internal:*)
      case "$1" in
        *\|internal:0)
          return 0
          ;;
      esac
      profile_mismatch laptop && return 0
      workspace_mismatch 1 "${LID_INTERNAL_OUTPUT}" && return 0
      workspace_mismatch 2 "${LID_INTERNAL_OUTPUT}" && return 0
      ;;
  esac

  return 1
}

last_state=""
iterations=0
reconcile_iterations=0

while :; do
  state="$(read_watch_state)"
  check_reconcile=0

  if [ "${state}" != "unknown" ]; then
    reconcile_iterations=$((reconcile_iterations + 1))
    if [ "${reconcile_iterations}" -ge "${LID_RECONCILE_INTERVAL}" ]; then
      reconcile_iterations=0
      check_reconcile=1
    fi
  fi

  if [ "${state}" != "unknown" ] && { [ "${state}" != "${last_state}" ] || { [ "${check_reconcile}" -eq 1 ] && needs_reconcile "${state}"; }; }; then
    sleep "${LID_SETTLE_DELAY}"
    state="$(read_watch_state)"

    if [ "${state}" != "unknown" ] && { [ "${state}" != "${last_state}" ] || needs_reconcile "${state}"; }; then
      last_state="${state}"
      run_handler
    fi
  fi

  if [ -n "${LID_WATCH_ITERATIONS}" ]; then
    iterations=$((iterations + 1))
    if [ "${iterations}" -ge "${LID_WATCH_ITERATIONS}" ]; then
      exit 0
    fi
  fi

  sleep "${LID_POLL_INTERVAL}"
done
