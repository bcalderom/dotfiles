#!/usr/bin/env bash
set -euo pipefail

LID_STATE_PATH="${LID_STATE_PATH:-/proc/acpi/button/lid/LID0/state}"
LID_HANDLER="${LID_HANDLER:-${HOME}/.config/hypr/scripts/lid.sh}"
LID_POLL_INTERVAL="${LID_POLL_INTERVAL:-1}"
LID_SETTLE_DELAY="${LID_SETTLE_DELAY:-0.5}"
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

last_state=""
iterations=0

while :; do
  state="$(read_watch_state)"

  if [ "${state}" != "unknown" ] && [ "${state}" != "${last_state}" ]; then
    sleep "${LID_SETTLE_DELAY}"
    state="$(read_watch_state)"

    if [ "${state}" != "unknown" ] && [ "${state}" != "${last_state}" ]; then
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
