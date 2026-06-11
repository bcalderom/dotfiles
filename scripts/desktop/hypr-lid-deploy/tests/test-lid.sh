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
: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"
: > "${LID_STATE_PATH}"
export HYPRCTL_LOG KANSHI_LOG LID_STATE_PATH

cat > "${MOCK_BIN}/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$0" "$@" >> "${HYPRCTL_LOG}"
printf '\n' >> "${HYPRCTL_LOG}"

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
    esac
    ;;
  activeworkspace)
    printf 'workspace ID %s (%s) on monitor %s:\n' "${HYPR_ACTIVE_WS:-2}" "${HYPR_ACTIVE_WS:-2}" "${HYPR_ACTIVE_MONITOR:-DP-1}"
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

echo "==> auto-detect closed state"
printf 'state: closed\n' > "${LID_STATE_PATH}"
HYPR_MONITORS=external run_lid

grep -Fq -- "switch docked_dp_hdmi" "${KANSHI_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword monitor eDP-1\\,disable" "${HYPRCTL_LOG}"
assert_waybar_restart

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> auto-detect open state"
printf 'state: open\n' > "${LID_STATE_PATH}"
HYPR_MONITORS=both HYPR_ACTIVE_WS=2 run_lid

grep -Fq -- "switch docked_open_dp_hdmi" "${KANSHI_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 eDP-1" "${HYPRCTL_LOG}"
assert_waybar_restart

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> closed docked fallback"
HYPR_MONITORS=external KANSHI_FAIL_HDMI=1 run_lid closed

grep -Fq -- "switch docked_dp_hdmi" "${KANSHI_LOG}"
grep -Fq -- "switch docked_dp_only" "${KANSHI_LOG}"
grep -Fq -- "keyword workspace 1\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword monitor eDP-1\\,disable" "${HYPRCTL_LOG}"
assert_waybar_restart

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
grep -Fq -- "keyword workspace 2\\,monitor:eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 eDP-1" "${HYPRCTL_LOG}"
assert_waybar_restart

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> open while docked from workspace 1"
HYPR_MONITORS=both HYPR_ACTIVE_WS=1 run_lid open

grep -Fq -- "switch docked_open_dp_hdmi" "${KANSHI_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 2" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 1" "${HYPRCTL_LOG}"
assert_waybar_restart

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> open while docked from extra workspace"
HYPR_MONITORS=both HYPR_ACTIVE_WS=3 run_lid open

grep -Fq -- "switch docked_open_dp_hdmi" "${KANSHI_LOG}"
grep -Fq -- "keyword workspace 1\\,monitor:DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 DP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "dispatch workspace 2" "${HYPRCTL_LOG}"
if grep -Fq -- "moveworkspacetomonitor 3 eDP-1" "${HYPRCTL_LOG}"; then
  echo "Did not expect extra workspace relocation during docked-open mapping" >&2
  exit 1
fi
assert_waybar_restart

: > "${HYPRCTL_LOG}"
: > "${KANSHI_LOG}"

echo "==> open after unplug"
HYPR_MONITORS=internal HYPR_ACTIVE_WS=2 run_lid open

grep -Fq -- "switch laptop" "${KANSHI_LOG}"
grep -Fq -- "dispatch dpms on eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 1\\,monitor:eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "keyword workspace 2\\,monitor:eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 1 eDP-1" "${HYPRCTL_LOG}"
grep -Fq -- "moveworkspacetomonitor 2 eDP-1" "${HYPRCTL_LOG}"
assert_waybar_restart

echo "OK"
