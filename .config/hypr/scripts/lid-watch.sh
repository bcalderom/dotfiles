#!/usr/bin/env bash
set -euo pipefail

LID_STATE_PATH="${LID_STATE_PATH:-/proc/acpi/button/lid/LID0/state}"
LID_HANDLER="${LID_HANDLER:-${HOME}/.config/hypr/scripts/lid.sh}"
LID_POLL_INTERVAL="${LID_POLL_INTERVAL:-1}"
LID_WATCH_ITERATIONS="${LID_WATCH_ITERATIONS:-}"

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

last_state=""
iterations=0

while :; do
  state="$(read_lid_state)"

  if [ "${state}" != "unknown" ] && [ "${state}" != "${last_state}" ]; then
    last_state="${state}"
    run_handler
  fi

  if [ -n "${LID_WATCH_ITERATIONS}" ]; then
    iterations=$((iterations + 1))
    if [ "${iterations}" -ge "${LID_WATCH_ITERATIONS}" ]; then
      exit 0
    fi
  fi

  sleep "${LID_POLL_INTERVAL}"
done
