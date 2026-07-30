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
RULE_STATE_PATH="${TMPDIR}/rule-state"
HANDLER_LOG="${TMPDIR}/handler.log"
LID_HANDLER="${TMPDIR}/lid-handler"
HYPR_LID_ACTIVE_WORKSPACE_FILE="${TMPDIR}/active-workspace"
export LID_STATE_PATH MONITOR_STATE_PATH RULE_STATE_PATH HANDLER_LOG LID_HANDLER HYPR_LID_ACTIVE_WORKSPACE_FILE

cat > "${MOCK_BIN}/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${HYPR_UNAVAILABLE:-0}" -eq 1 ]] && exit 1

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
        internal_ws=3
        if [[ "$(cat "${RULE_STATE_PATH}")" == "wrong-auto" ]]; then
          internal_ws=4
        fi
        printf 'Monitor DP-1 (ID 1):\n'
        printf '\tactive workspace: 2 (2)\n'
        printf 'Monitor eDP-1 (ID 0):\n'
        printf '\tactive workspace: %s (%s)\n' "${internal_ws}" "${internal_ws}"
        ;;
      mirror)
        printf 'Monitor eDP-1 (ID 0):\n'
        printf '\tactive workspace: 2 (2)\n'
        printf 'Monitor HDMI-A-1 (ID 2):\n'
        ;;
      external)
        printf 'Monitor DP-1 (ID 1):\n'
        printf '\tactive workspace: 2 (2)\n'
        ;;
      internal)
        printf 'Monitor eDP-1 (ID 0):\n'
        printf '\tactive workspace: 2 (2)\n'
        ;;
    esac
    ;;
  workspacerules)
    if [[ "${HYPRLAND_INSTANCE_SIGNATURE:-}" != "test-signature" || "${WAYLAND_DISPLAY:-}" != "wayland-test" ]]; then
      exit 1
    fi

    case "$(cat "${RULE_STATE_PATH}")" in
      docked)
        printf '[{"workspaceString":"1","monitor":"DP-1"},{"workspaceString":"2","monitor":"DP-1"},{"workspaceString":"3","monitor":"DP-1","persistent":false}]\n'
        ;;
      docked-open)
        printf '[{"workspaceString":"1","monitor":"DP-1"},{"workspaceString":"2","monitor":"DP-1"},{"workspaceString":"3","monitor":"eDP-1","persistent":false}]\n'
        ;;
      wrong-auto)
        printf '[{"workspaceString":"1","monitor":"DP-1"},{"workspaceString":"2","monitor":"DP-1"},{"workspaceString":"3","monitor":"eDP-1","persistent":false}]\n'
        ;;
      laptop)
        printf '[{"workspaceString":"1","monitor":"eDP-1"},{"workspaceString":"2","monitor":"eDP-1"},{"workspaceString":"3","monitor":"eDP-1","persistent":false}]\n'
        ;;
      mirror)
        printf '[{"workspaceString":"1","monitor":"eDP-1"},{"workspaceString":"2","monitor":"eDP-1"},{"workspaceString":"3","monitor":"eDP-1","persistent":false}]\n'
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
        printf 'workspace ID 3 (3) on monitor DP-1:\n'
        ;;
      docked-open)
        printf 'workspace ID 1 (1) on monitor DP-1:\n'
        printf 'workspace ID 2 (2) on monitor DP-1:\n'
        printf 'workspace ID 3 (3) on monitor eDP-1:\n'
        ;;
      wrong-auto)
        printf 'workspace ID 1 (1) on monitor DP-1:\n'
        printf 'workspace ID 2 (2) on monitor DP-1:\n'
        printf 'workspace ID 4 (4) on monitor eDP-1:\n'
        ;;
      laptop)
        printf 'workspace ID 1 (1) on monitor eDP-1:\n'
        printf 'workspace ID 2 (2) on monitor eDP-1:\n'
        printf 'workspace ID 3 (3) on monitor eDP-1:\n'
        ;;
      mirror)
        printf 'workspace ID 1 (1) on monitor eDP-1:\n'
        printf 'workspace ID 2 (2) on monitor eDP-1:\n'
        printf 'workspace ID 3 (3) on monitor eDP-1:\n'
        ;;
    esac
    ;;
esac
EOF
chmod +x "${MOCK_BIN}/hyprctl"

cat > "${LID_HANDLER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

lid_state="$1"
monitor_state="$(cat "${MONITOR_STATE_PATH}")"

if [[ "${HYPRLAND_INSTANCE_SIGNATURE:-}" != "test-signature" || "${WAYLAND_DISPLAY:-}" != "wayland-test" ]]; then
  printf 'missing-hyprland-env\n' >> "${HANDLER_LOG}"
  exit 1
fi

printf '%s %s %s\n' "${lid_state}" "${monitor_state}" "$(cat "${RULE_STATE_PATH}")" >> "${HANDLER_LOG}"

if [[ "${HYPR_HANDLER_FAIL:-0}" -eq 1 ]]; then
  exit 1
fi

case "${lid_state}:${monitor_state}" in
  closed:both)
    printf 'docked\n' > "${RULE_STATE_PATH}"
    ;;
  closed:external)
    printf 'both\n' > "${MONITOR_STATE_PATH}"
    printf 'docked\n' > "${RULE_STATE_PATH}"
    ;;
  open:both)
    printf 'docked-open\n' > "${RULE_STATE_PATH}"
    ;;
  open:internal)
    printf 'laptop\n' > "${RULE_STATE_PATH}"
    ;;
  open:mirror)
    printf 'mirror\n' > "${RULE_STATE_PATH}"
    ;;
esac
EOF
chmod +x "${LID_HANDLER}"
printf 'state: closed\n' > "${LID_STATE_PATH}"
printf 'both\n' > "${MONITOR_STATE_PATH}"
printf 'docked\n' > "${RULE_STATE_PATH}"
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0 LID_STABLE_SAMPLES=3 LID_RECONCILE_INTERVAL=1 LID_WATCH_ITERATIONS=20 bash "${WATCH_SCRIPT}" &
watch_pid="$!"
sleep 0.15
printf 'state: open\n' > "${LID_STATE_PATH}"
printf 'both\n' > "${MONITOR_STATE_PATH}"
wait "${watch_pid}"
grep -Fq 'closed both' "${HANDLER_LOG}"
grep -Fq 'open both' "${HANDLER_LOG}"
if [[ "$(grep -Fc 'closed ' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one closed transition after the handler changed topology" >&2
  exit 1
fi
if [[ "$(grep -Fc 'open both' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one open transition" >&2
  exit 1
fi
: > "${HANDLER_LOG}"
printf 'state: open\n' > "${LID_STATE_PATH}"
printf 'internal\n' > "${MONITOR_STATE_PATH}"
printf 'laptop\n' > "${RULE_STATE_PATH}"
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0 LID_STABLE_SAMPLES=3 LID_RECONCILE_INTERVAL=100 LID_WATCH_ITERATIONS=40 bash "${WATCH_SCRIPT}" &
watch_pid="$!"
sleep 0.3
printf 'both\n' > "${MONITOR_STATE_PATH}"
sleep 0.3
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
printf 'docked\n' > "${RULE_STATE_PATH}"
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0 LID_STABLE_SAMPLES=3 LID_RECONCILE_INTERVAL=1 LID_WATCH_ITERATIONS=20 bash "${WATCH_SCRIPT}" &
watch_pid="$!"
sleep 0.15
printf 'laptop\n' > "${RULE_STATE_PATH}"
wait "${watch_pid}"
if [[ "$(grep -Fc 'closed both laptop' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one stable-state mismatch reconciliation" >&2
  exit 1
fi
: > "${HANDLER_LOG}"
printf 'state: open\n' > "${LID_STATE_PATH}"
printf 'both\n' > "${MONITOR_STATE_PATH}"
printf 'docked-open\n' > "${RULE_STATE_PATH}"
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0 LID_STABLE_SAMPLES=3 LID_RECONCILE_INTERVAL=1 LID_WATCH_ITERATIONS=20 bash "${WATCH_SCRIPT}" &
watch_pid="$!"
sleep 0.15
printf 'wrong-auto\n' > "${RULE_STATE_PATH}"
wait "${watch_pid}"
if [[ "$(grep -Fc 'open both wrong-auto' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one dynamic workspace reconciliation" >&2
  exit 1
fi
: > "${HANDLER_LOG}"
printf 'state: open\n' > "${LID_STATE_PATH}"
printf 'mirror\n' > "${MONITOR_STATE_PATH}"
printf 'laptop\n' > "${RULE_STATE_PATH}"
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0 LID_STABLE_SAMPLES=3 LID_RECONCILE_INTERVAL=1 LID_WATCH_ITERATIONS=20 bash "${WATCH_SCRIPT}" &
watch_pid="$!"
wait "${watch_pid}"
if [[ "$(grep -Fc 'open mirror laptop' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one HDMI mirror reconciliation" >&2
  exit 1
fi
: > "${HANDLER_LOG}"
printf 'state: open\n' > "${LID_STATE_PATH}"
printf 'internal\n' > "${MONITOR_STATE_PATH}"
printf 'laptop\n' > "${RULE_STATE_PATH}"
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0.1 LID_STABLE_SAMPLES=6 LID_RECONCILE_INTERVAL=10 LID_WATCH_ITERATIONS=45 bash "${WATCH_SCRIPT}" &
watch_pid="$!"
sleep 0.7
: > "${HANDLER_LOG}"
printf 'both\n' > "${MONITOR_STATE_PATH}"
sleep 0.03
printf 'internal\n' > "${MONITOR_STATE_PATH}"
wait "${watch_pid}"
if grep -Fq 'open both' "${HANDLER_LOG}"; then
  echo "Did not expect a transient topology to be handled" >&2
  exit 1
fi
: > "${HANDLER_LOG}"
printf 'state: open\n' > "${LID_STATE_PATH}"
printf 'internal\n' > "${MONITOR_STATE_PATH}"
printf 'laptop\n' > "${RULE_STATE_PATH}"
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY PATH="${MOCK_BIN}:${PATH}" HYPR_HANDLER_FAIL=1 LID_POLL_INTERVAL=0.05 LID_SETTLE_DELAY=0 LID_STABLE_SAMPLES=3 LID_RECONCILE_INTERVAL=1 LID_FAILURE_INITIAL_BACKOFF=5 LID_FAILURE_MAX_BACKOFF=5 LID_WATCH_ITERATIONS=8 bash "${WATCH_SCRIPT}" &
watch_pid="$!"
wait "${watch_pid}"
if [[ "$(grep -Fc 'open internal laptop' "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected failed handler state to be retried only after backoff" >&2
  exit 1
fi
: > "${HANDLER_LOG}"
HYPR_UNAVAILABLE=1 PATH="${MOCK_BIN}:${PATH}" LID_POLL_INTERVAL=0 LID_SETTLE_DELAY=0 LID_WATCH_ITERATIONS=3 bash "${WATCH_SCRIPT}"
[[ ! -s "${HANDLER_LOG}" ]] || { echo "Did not expect handling without Hyprland" >&2; exit 1; }
echo "OK"
