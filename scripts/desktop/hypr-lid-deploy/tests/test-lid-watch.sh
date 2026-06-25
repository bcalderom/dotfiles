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
PROFILE_STATE_PATH="${TMPDIR}/profile-state"
RULE_STATE_PATH="${TMPDIR}/rule-state"
HANDLER_LOG="${TMPDIR}/handler.log"
LID_HANDLER="${TMPDIR}/lid-handler"
export LID_STATE_PATH MONITOR_STATE_PATH PROFILE_STATE_PATH RULE_STATE_PATH HANDLER_LOG LID_HANDLER

cat > "${MOCK_BIN}/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  -j)
    shift
    ;;
esac

case "${1:-}" in
  instances)
    printf 'instance test-signature:\n'
    printf '\ttime: 1\n'
    printf '\tpid: 123\n'
    printf '\twl socket: wayland-test\n'
    ;;
  monitors)
    if [[ "${HYPRLAND_INSTANCE_SIGNATURE:-}" != "test-signature" || "${WAYLAND_DISPLAY:-}" != "wayland-test" ]]; then
      exit 1
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
    ;;
  workspacerules)
    if [[ "${HYPRLAND_INSTANCE_SIGNATURE:-}" != "test-signature" || "${WAYLAND_DISPLAY:-}" != "wayland-test" ]]; then
      exit 1
    fi

    case "$(cat "${RULE_STATE_PATH}")" in
      docked)
        printf '[{"workspaceString":"1","monitor":"DP-1"},{"workspaceString":"2","monitor":"DP-1"}]\n'
        ;;
      docked-open)
        printf '[{"workspaceString":"1","monitor":"DP-1"},{"workspaceString":"2","monitor":"eDP-1"}]\n'
        ;;
      laptop)
        printf '[{"workspaceString":"1","monitor":"eDP-1"},{"workspaceString":"2","monitor":"eDP-1"}]\n'
        ;;
    esac
    ;;
  workspaces)
    if [[ "${HYPRLAND_INSTANCE_SIGNATURE:-}" != "test-signature" || "${WAYLAND_DISPLAY:-}" != "wayland-test" ]]; then
      exit 1
    fi

    case "$(cat "${RULE_STATE_PATH}")" in
      docked)
        printf 'workspace ID 1 (1) on monitor DP-1:\n'
        printf 'workspace ID 2 (2) on monitor DP-1:\n'
        ;;
      docked-open)
        printf 'workspace ID 1 (1) on monitor DP-1:\n'
        printf 'workspace ID 2 (2) on monitor eDP-1:\n'
        ;;
      laptop)
        printf 'workspace ID 1 (1) on monitor eDP-1:\n'
        printf 'workspace ID 2 (2) on monitor eDP-1:\n'
        ;;
    esac
    ;;
esac
EOF
chmod +x "${MOCK_BIN}/hyprctl"

cat > "${MOCK_BIN}/kanshictl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "status" ]]; then
  if [[ "${HYPRLAND_INSTANCE_SIGNATURE:-}" != "test-signature" || "${WAYLAND_DISPLAY:-}" != "wayland-test" ]]; then
    exit 1
  fi

  printf 'Current profile: %s\n' "$(cat "${PROFILE_STATE_PATH}")"
fi
EOF
chmod +x "${MOCK_BIN}/kanshictl"

cat > "${LID_HANDLER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

lid_state="$(grep -o 'closed\|open' "${LID_STATE_PATH}")"
monitor_state="$(cat "${MONITOR_STATE_PATH}")"

if [[ "${HYPRLAND_INSTANCE_SIGNATURE:-}" != "test-signature" || "${WAYLAND_DISPLAY:-}" != "wayland-test" ]]; then
  printf 'missing-hyprland-env\n' >> "${HANDLER_LOG}"
  exit 1
fi

printf '%s %s %s %s\n' "${lid_state}" "${monitor_state}" "$(cat "${PROFILE_STATE_PATH}")" "$(cat "${RULE_STATE_PATH}")" >> "${HANDLER_LOG}"

case "${lid_state}:${monitor_state}" in
  closed:external|closed:both)
    printf 'docked_dp_only\n' > "${PROFILE_STATE_PATH}"
    printf 'docked\n' > "${RULE_STATE_PATH}"
    ;;
  open:both)
    printf 'docked_open_dp_only\n' > "${PROFILE_STATE_PATH}"
    printf 'docked-open\n' > "${RULE_STATE_PATH}"
    ;;
  open:internal)
    printf 'laptop\n' > "${PROFILE_STATE_PATH}"
    printf 'laptop\n' > "${RULE_STATE_PATH}"
    ;;
esac
EOF
chmod +x "${LID_HANDLER}"

printf 'state: closed\n' > "${LID_STATE_PATH}"
printf 'external\n' > "${MONITOR_STATE_PATH}"
printf 'docked_dp_only\n' > "${PROFILE_STATE_PATH}"
printf 'docked\n' > "${RULE_STATE_PATH}"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0 LID_RECONCILE_INTERVAL=1 LID_WATCH_ITERATIONS=20 bash "${WATCH_SCRIPT}" &
watch_pid="$!"

sleep 0.15
printf 'state: open\n' > "${LID_STATE_PATH}"
printf 'both\n' > "${MONITOR_STATE_PATH}"

wait "${watch_pid}"

grep -Fq 'closed external' "${HANDLER_LOG}"
grep -Fq 'open both' "${HANDLER_LOG}"

if [[ "$(grep -Fc 'closed external' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one closed transition" >&2
  exit 1
fi

if [[ "$(grep -Fc 'open both' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one open transition" >&2
  exit 1
fi

: > "${HANDLER_LOG}"
printf 'state: open\n' > "${LID_STATE_PATH}"
printf 'internal\n' > "${MONITOR_STATE_PATH}"
printf 'laptop\n' > "${PROFILE_STATE_PATH}"
printf 'laptop\n' > "${RULE_STATE_PATH}"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0 LID_RECONCILE_INTERVAL=1 LID_WATCH_ITERATIONS=25 bash "${WATCH_SCRIPT}" &
watch_pid="$!"

sleep 0.15
printf 'both\n' > "${MONITOR_STATE_PATH}"

sleep 0.15
printf 'internal\n' > "${MONITOR_STATE_PATH}"

wait "${watch_pid}"

grep -Fq 'open both' "${HANDLER_LOG}"

if [[ "$(grep -Fc 'open internal' "${HANDLER_LOG}")" -ne 2 ]]; then
  echo "Expected initial and disconnected internal-only transitions" >&2
  exit 1
fi

if [[ "$(grep -Fc 'open both' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one external monitor connect transition" >&2
  exit 1
fi

: > "${HANDLER_LOG}"
printf 'state: closed\n' > "${LID_STATE_PATH}"
printf 'external\n' > "${MONITOR_STATE_PATH}"
printf 'docked_dp_only\n' > "${PROFILE_STATE_PATH}"
printf 'docked\n' > "${RULE_STATE_PATH}"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0 LID_RECONCILE_INTERVAL=1 LID_WATCH_ITERATIONS=20 bash "${WATCH_SCRIPT}" &
watch_pid="$!"

sleep 0.15
printf 'laptop\n' > "${PROFILE_STATE_PATH}"
printf 'laptop\n' > "${RULE_STATE_PATH}"

wait "${watch_pid}"

if [[ "$(grep -Fc 'closed external laptop laptop' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one stable-state mismatch reconciliation" >&2
  exit 1
fi

echo "OK"
