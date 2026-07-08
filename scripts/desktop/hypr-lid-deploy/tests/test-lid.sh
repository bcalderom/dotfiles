#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)"
LID_SCRIPT="${DOTFILES_DIR}/.config/hypr/scripts/lid.sh"

if [[ ! -f "${LID_SCRIPT}" ]]; then
  echo "Missing: ${LID_SCRIPT}" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

MOCK_BIN="${TMPDIR}/bin"
mkdir -p "${MOCK_BIN}"

HYPRCTL_LOG="${TMPDIR}/hyprctl.log"
KANSHI_LOG="${TMPDIR}/kanshi.log"
LID_STATE_PATH="${TMPDIR}/lid-state"
HYPR_LID_ACTIVE_WORKSPACE_FILE="${TMPDIR}/active-workspace"
: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"
: > "${LID_STATE_PATH}"
export HYPRCTL_LOG KANSHI_LOG LID_STATE_PATH HYPR_LID_ACTIVE_WORKSPACE_FILE

cat > "${MOCK_BIN}/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$0" "$@" >> "${HYPRCTL_LOG}"
printf '\n' >> "${HYPRCTL_LOG}"

ws() { printf 'workspace ID %s (%s) on monitor %s:\n\twindows: %s\n' "$1" "$1" "$2" "$3"; }

case "${1:-}" in
  monitors)
    case "${HYPR_MONITORS:-both}" in
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
      mirror)
        printf 'Monitor eDP-1 (ID 0):\n'
        printf 'Monitor HDMI-A-1 (ID 2):\n'
        ;;
    esac
    ;;
  activeworkspace)
    printf 'workspace ID %s (%s) on monitor %s:\n' "${HYPR_ACTIVE_WS:-2}" "${HYPR_ACTIVE_WS:-2}" "${HYPR_ACTIVE_MONITOR:-DP-1}"
    ;;
  workspaces)
    case "${HYPR_WORKSPACES:-external12}" in
      external12)
        ws 1 DP-1 1
        ws 2 DP-1 1
        ;;
      external123)
        ws 1 DP-1 1
        ws 2 DP-1 1
        ws 3 DP-1 1
        ;;
      both12auto4)
        ws 1 DP-1 1
        ws 2 DP-1 1
        ws 4 eDP-1 0
        ;;
      internal12)
        ws 1 eDP-1 1
        ws 2 eDP-1 1
        ;;
      internal12auto4)
        ws 1 eDP-1 1
        ws 2 eDP-1 1
        ws 4 eDP-1 0
        ;;
    esac
    ;;
esac

exit 0
EOF
chmod +x "${MOCK_BIN}/hyprctl"

cat > "${MOCK_BIN}/kanshictl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$0" "$@" >> "${KANSHI_LOG}"
printf '\n' >> "${KANSHI_LOG}"

if [[ "${1:-}" == "switch" ]]; then
  case "${2:-}" in
    docked_dp_hdmi|docked_open_dp_hdmi)
      if [[ "${KANSHI_FAIL_HDMI:-0}" -eq 1 ]]; then
        exit 1
      fi
      ;;
  esac
fi

exit 0
EOF
chmod +x "${MOCK_BIN}/kanshictl"

cat > "${MOCK_BIN}/pgrep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "${MOCK_BIN}/pgrep"

run_lid() {
  PATH="${MOCK_BIN}:${PATH}" bash "${LID_SCRIPT}" "$@"
}

assert_waybar_restart() {
  grep -Fq -- "dispatch exec bash\\ -lc" "${HYPRCTL_LOG}"
  grep -Fq -- "waybar" "${HYPRCTL_LOG}"
}

assert_no_persistent_workspace() {
  if grep -Fq -- "persistent:true" "${HYPRCTL_LOG}"; then
    echo "Workspace 3 should be monitor-bound but not persistent" >&2
    exit 1
  fi
}

echo "==> auto-detect closed state"
printf 'state: closed\n' > "${LID_STATE_PATH}"
HYPR_MONITORS=external run_lid

grep -Fq -- "switch docked_dp_hdmi" "${KANSHI_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 3\\,monitor:DP-1\\,persistent:false" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 3 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 2" "${HYPRCTL_LOG}"
grep -Fq -- "keyword monitor eDP-1\\,disable" "${HYPRCTL_LOG}"
assert_waybar_restart
assert_no_persistent_workspace

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> auto-detect open state"
printf 'state: open\n' > "${LID_STATE_PATH}"
HYPR_MONITORS=both HYPR_ACTIVE_WS=2 run_lid

grep -Fq -- "switch docked_open_dp_hdmi" "${KANSHI_LOG}"
grep -Fq -- "keyword workspace 1\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 3\\,monitor:eDP-1\\,persistent:false" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 3" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 3 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 2" "${HYPRCTL_LOG}"
assert_waybar_restart
assert_no_persistent_workspace

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> closed docked fallback"
HYPR_MONITORS=external KANSHI_FAIL_HDMI=1 run_lid closed

grep -Fq -- "switch docked_dp_hdmi" "${KANSHI_LOG}"
grep -Fq -- "switch docked_dp_only" "${KANSHI_LOG}"
grep -Fq -- "keyword workspace 1\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 3\\,monitor:DP-1\\,persistent:false" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 3 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 2" "${HYPRCTL_LOG}"
grep -Fq -- "keyword monitor eDP-1\\,disable" "${HYPRCTL_LOG}"
assert_waybar_restart
assert_no_persistent_workspace

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> open while docked"
HYPR_MONITORS=both HYPR_ACTIVE_WS=2 run_lid open

grep -Fq -- "switch docked_open_dp_hdmi" "${KANSHI_LOG}"
if grep -Fq -- "switch laptop" "${KANSHI_LOG}"; then
  echo "Did not expect laptop profile while DP-1 is present" >&2
  exit 1
fi
grep -Fq -- "dispatch dpms on eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 1\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 3\\,monitor:eDP-1\\,persistent:false" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 3" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 3 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 2" "${HYPRCTL_LOG}"
assert_waybar_restart
assert_no_persistent_workspace

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> open while docked from workspace 1"
HYPR_MONITORS=both HYPR_ACTIVE_WS=1 run_lid open

grep -Fq -- "switch docked_open_dp_hdmi" "${KANSHI_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 3" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 3 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 1" "${HYPRCTL_LOG}"
assert_waybar_restart
assert_no_persistent_workspace

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> open while docked from extra workspace"
HYPR_MONITORS=both HYPR_WORKSPACES=external123 HYPR_ACTIVE_WS=3 run_lid open

grep -Fq -- "switch docked_open_dp_hdmi" "${KANSHI_LOG}"
grep -Fq -- "keyword workspace 1\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 3\\,monitor:DP-1\\,persistent:false" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 4\\,monitor:eDP-1\\,persistent:false" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 4" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 4 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 3" "${HYPRCTL_LOG}"
assert_waybar_restart
assert_no_persistent_workspace

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> open while docked with auto workspace"
HYPR_MONITORS=both HYPR_WORKSPACES=both12auto4 HYPR_ACTIVE_WS=4 HYPR_ACTIVE_MONITOR=eDP-1 run_lid open

grep -Fq -- "switch docked_open_dp_hdmi" "${KANSHI_LOG}"
grep -Fq -- "keyword workspace 3\\,monitor:eDP-1\\,persistent:false" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 3" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 3 eDP-1" "${HYPRCTL_LOG}"
if grep -Fq -- "dispatch workspace 4" "${HYPRCTL_LOG}"; then echo "Did not expect the wrong auto workspace to be restored" >&2; exit 1; fi
assert_waybar_restart
assert_no_persistent_workspace

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> open after unplug"
printf '2\n' > "${HYPR_LID_ACTIVE_WORKSPACE_FILE}"
HYPR_MONITORS=internal HYPR_WORKSPACES=internal12auto4 HYPR_ACTIVE_WS=4 HYPR_ACTIVE_MONITOR=eDP-1 run_lid open

grep -Fq -- "switch laptop" "${KANSHI_LOG}"
grep -Fq -- "dispatch dpms on eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 1\\,monitor:eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 3\\,monitor:eDP-1\\,persistent:false" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 3 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 2" "${HYPRCTL_LOG}"
if grep -Fq -- "dispatch workspace 4" "${HYPRCTL_LOG}"; then echo "Did not expect unplug recovery to restore the auto workspace" >&2; exit 1; fi
assert_waybar_restart
assert_no_persistent_workspace

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> open with HDMI mirror"
HYPR_MONITORS=mirror HYPR_ACTIVE_WS=2 run_lid open

grep -Fq -- "switch mirror" "${KANSHI_LOG}"
grep -Fq -- "keyword monitor HDMI-A-1\\,1920x1080@60\\,0x0\\,1\\,mirror\\,eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 1\\,monitor:eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 3\\,monitor:eDP-1\\,persistent:false" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 3 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 2" "${HYPRCTL_LOG}"
assert_waybar_restart
assert_no_persistent_workspace

echo "OK"
