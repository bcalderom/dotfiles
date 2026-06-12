#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)"
WATCH_SCRIPT="${DOTFILES_DIR}/.config/hypr/scripts/lid-watch.sh"

if [[ ! -f "${WATCH_SCRIPT}" ]]; then
  echo "Missing: ${WATCH_SCRIPT}" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

MOCK_BIN="${TMPDIR}/bin"
mkdir -p "${MOCK_BIN}"

LID_STATE_PATH="${TMPDIR}/lid-state"
MONITOR_STATE_PATH="${TMPDIR}/monitor-state"
HANDLER_LOG="${TMPDIR}/handler.log"
LID_HANDLER="${TMPDIR}/lid-handler"
export LID_STATE_PATH MONITOR_STATE_PATH HANDLER_LOG LID_HANDLER

cat > "${MOCK_BIN}/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "monitors" ]]; then
  exit 0
fi

case "$(cat "${MONITOR_STATE_PATH}")" in
  both)
    printf 'Monitor DP-1 (ID 1):\n'
    printf 'Monitor eDP-1 (ID 0):\n'
    ;;
  external)
    printf 'Monitor DP-1 (ID 1):\n'
    ;;
  internal)
    printf 'Monitor eDP-1 (ID 0):\n'
    ;;
esac
EOF
chmod +x "${MOCK_BIN}/hyprctl"

cat > "${LID_HANDLER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s %s\n' "$(grep -o 'closed\|open' "${LID_STATE_PATH}")" "$(cat "${MONITOR_STATE_PATH}")" >> "${HANDLER_LOG}"
EOF
chmod +x "${LID_HANDLER}"

printf 'state: closed\n' > "${LID_STATE_PATH}"
printf 'external\n' > "${MONITOR_STATE_PATH}"

PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0 LID_WATCH_ITERATIONS=20 bash "${WATCH_SCRIPT}" &
watch_pid="$!"

sleep 0.15
printf 'state: open\n' > "${LID_STATE_PATH}"
printf 'both\n' > "${MONITOR_STATE_PATH}"

wait "${watch_pid}"

grep -Fxq 'closed external' "${HANDLER_LOG}"
grep -Fxq 'open both' "${HANDLER_LOG}"

if [[ "$(grep -Fxc 'closed external' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one closed transition" >&2
  exit 1
fi

if [[ "$(grep -Fxc 'open both' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one open transition" >&2
  exit 1
fi

: > "${HANDLER_LOG}"
printf 'state: open\n' > "${LID_STATE_PATH}"
printf 'internal\n' > "${MONITOR_STATE_PATH}"

PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0 LID_WATCH_ITERATIONS=25 bash "${WATCH_SCRIPT}" &
watch_pid="$!"

sleep 0.15
printf 'both\n' > "${MONITOR_STATE_PATH}"

sleep 0.15
printf 'internal\n' > "${MONITOR_STATE_PATH}"

wait "${watch_pid}"

grep -Fxq 'open both' "${HANDLER_LOG}"

if [[ "$(grep -Fxc 'open internal' "${HANDLER_LOG}")" -ne 2 ]]; then
  echo "Expected initial and disconnected internal-only transitions" >&2
  exit 1
fi

if [[ "$(grep -Fxc 'open both' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one external monitor connect transition" >&2
  exit 1
fi

echo "OK"
