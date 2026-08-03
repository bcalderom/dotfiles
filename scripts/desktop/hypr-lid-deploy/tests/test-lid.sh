#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)"
LID_SCRIPT="${DOTFILES_DIR}/.config/hypr/scripts/lid.sh"

[[ -f "${LID_SCRIPT}" ]] || { echo "Missing: ${LID_SCRIPT}" >&2; exit 1; }

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

MOCK_BIN="${TMPDIR}/bin"
mkdir -p "${MOCK_BIN}"

HYPRCTL_LOG="${TMPDIR}/hyprctl.log"
ACTIVE_MONITORS_PATH="${TMPDIR}/active-monitors"
ALL_MONITORS_PATH="${TMPDIR}/all-monitors"
MONITOR_ATTEMPTS_PATH="${TMPDIR}/monitor-attempts"
LID_STATE_PATH="${TMPDIR}/lid-state"
HYPR_LID_ACTIVE_WORKSPACE_FILE="${TMPDIR}/active-workspace"
HYPR_LID_RECOVERY_FILE="${TMPDIR}/recovery"
HYPR_LID_BACKLIGHT_STATE_FILE="${TMPDIR}/backlight-state"
BACKLIGHT_VALUE_PATH="${TMPDIR}/backlight-value"
BACKLIGHT_LOG="${TMPDIR}/backlight.log"
AUDIO_ROUTE_LOG="${TMPDIR}/audio-route.log"
: > "${AUDIO_ROUTE_LOG}"
HYPR_LID_AUDIO_ROUTE_SCRIPT="${TMPDIR}/audio-route"
: > "${HYPRCTL_LOG}"
: > "${LID_STATE_PATH}"
printf '100\n' > "${BACKLIGHT_VALUE_PATH}"
: > "${BACKLIGHT_LOG}"
export HYPRCTL_LOG ACTIVE_MONITORS_PATH ALL_MONITORS_PATH MONITOR_ATTEMPTS_PATH LID_STATE_PATH HYPR_LID_ACTIVE_WORKSPACE_FILE HYPR_LID_RECOVERY_FILE HYPR_LID_BACKLIGHT_STATE_FILE BACKLIGHT_VALUE_PATH BACKLIGHT_LOG AUDIO_ROUTE_LOG HYPR_LID_AUDIO_ROUTE_SCRIPT

cat > "${HYPR_LID_AUDIO_ROUTE_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
printf 'route\n' >> "${AUDIO_ROUTE_LOG}"
EOF
chmod +x "${HYPR_LID_AUDIO_ROUTE_SCRIPT}"

cat > "${MOCK_BIN}/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$0" "$@" >> "${HYPRCTL_LOG}"
printf '\n' >> "${HYPRCTL_LOG}"

print_monitors() {
  while IFS= read -r monitor; do
    [[ -n "${monitor}" ]] && printf 'Monitor %s (ID 1):\n' "${monitor}"
  done < "$1"
}

set_monitor_state() {
  local monitor="$1"
  local enabled="$2"
  local tmp="${ACTIVE_MONITORS_PATH}.tmp"

  while IFS= read -r current; do
    [[ "${current}" != "${monitor}" ]] && printf '%s\n' "${current}"
  done < "${ACTIVE_MONITORS_PATH}" > "${tmp}"
  [[ "${enabled}" -eq 1 ]] && printf '%s\n' "${monitor}" >> "${tmp}"
  mv "${tmp}" "${ACTIVE_MONITORS_PATH}"
}

maybe_skip_monitor_enable() {
  local monitor="$1"
  local marker="${MONITOR_ATTEMPTS_PATH}.${monitor}"

  if [[ "${HYPR_MONITOR_FALSE_SUCCESS_ONCE:-}" == "${monitor}" && ! -e "${marker}" ]]; then
    touch "${marker}"
    return 0
  fi

  return 1
}

ws() { printf 'workspace ID %s (%s) on monitor %s:\n\twindows: %s\n' "$1" "$1" "$2" "$3"; }

case "${1:-}" in
  monitors)
    if [[ "${2:-}" == "all" ]]; then
      print_monitors "${ALL_MONITORS_PATH}"
    else
      print_monitors "${ACTIVE_MONITORS_PATH}"
    fi
    ;;
  activeworkspace)
    printf 'workspace ID %s (%s) on monitor %s:\n' "${HYPR_ACTIVE_WS:-2}" "${HYPR_ACTIVE_WS:-2}" "${HYPR_ACTIVE_MONITOR:-DP-1}"
    ;;
  workspaces)
    case "${HYPR_WORKSPACES:-external12}" in
      external12) ws 1 DP-1 1; ws 2 DP-1 1 ;;
      external1empty23) ws 1 DP-1 1; ws 2 DP-1 0; ws 3 DP-1 0 ;;
      external123) ws 1 DP-1 1; ws 2 DP-1 1; ws 3 DP-1 1 ;;
      both12auto4) ws 1 DP-1 1; ws 2 DP-1 1; ws 4 eDP-1 0 ;;
      internal12) ws 1 eDP-1 1; ws 2 eDP-1 1 ;;
      internal12auto4) ws 1 eDP-1 1; ws 2 eDP-1 1; ws 4 eDP-1 0 ;;
    esac
    ;;
  keyword)
    if [[ "${2:-}" == "monitor" ]]; then
      monitor="${3%%,*}"
      if [[ "${3#*,}" == "disable" ]]; then
        set_monitor_state "${monitor}" 0
      else
        maybe_skip_monitor_enable "${monitor}" && exit 0
        set_monitor_state "${monitor}" 1
      fi
    fi
    ;;
  reload)
    [[ -n "${HYPR_RELOAD_RECOVERS:-}" ]] && set_monitor_state "${HYPR_RELOAD_RECOVERS}" 1
    ;;
esac
EOF
chmod +x "${MOCK_BIN}/hyprctl"

cat > "${MOCK_BIN}/brightnessctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$0" "$@" >> "${BACKLIGHT_LOG}"
printf '\n' >> "${BACKLIGHT_LOG}"
operation=""
for arg in "$@"; do
  if [[ "${operation}" == "set" ]]; then printf '%s\n' "${arg}" > "${BACKLIGHT_VALUE_PATH}"; exit 0; fi
  case "${arg}" in get) cat "${BACKLIGHT_VALUE_PATH}"; exit 0 ;; set) operation="set" ;; esac
done
EOF
chmod +x "${MOCK_BIN}/brightnessctl"

run_lid() { PATH="${MOCK_BIN}:${PATH}" bash "${LID_SCRIPT}" "$@"; }

set_monitors() {
  printf '%s\n' "$1" | tr ' ' '\n' > "${ACTIVE_MONITORS_PATH}"
  printf '%s\n' "$2" | tr ' ' '\n' > "${ALL_MONITORS_PATH}"
}

reset_log() { : > "${HYPRCTL_LOG}"; }

assert_contains() { grep -Fq -- "$1" "${HYPRCTL_LOG}"; }

assert_not_contains() {
  if grep -Fq -- "$1" "${HYPRCTL_LOG}"; then
    echo "Unexpected command: $1" >&2
    exit 1
  fi
}

assert_before() {
  local first second
  first="$(grep -Fn -- "$1" "${HYPRCTL_LOG}" | awk -F: 'NR == 1 { print $1 }')"
  second="$(grep -Fn -- "$2" "${HYPRCTL_LOG}" | awk -F: 'NR == 1 { print $1 }')"
  [[ -n "${first}" && -n "${second}" && "${first}" -lt "${second}" ]]
}

assert_no_process_restart() {
  assert_not_contains "waybar"
  assert_not_contains "pkill"
}

echo "==> close lid with active dock"
printf 'state: closed\n' > "${LID_STATE_PATH}"
set_monitors "DP-1 eDP-1" "DP-1 eDP-1"
HYPR_WORKSPACES=external1empty23 HYPR_ACTIVE_WS=1 run_lid

assert_contains "keyword workspace 1\\,monitor:DP-1\\,persistent:false"
assert_contains "keyword workspace 2\\,monitor:DP-1\\,persistent:false"
assert_contains "keyword workspace 10\\,monitor:DP-1\\,persistent:false"
assert_not_contains "moveworkspacetomonitor 2 DP-1"
assert_not_contains "moveworkspacetomonitor 3 DP-1"
assert_contains "keyword workspace 3\\,monitor:DP-1\\,persistent:false"
assert_contains "keyword monitor eDP-1\\,disable"
assert_before "moveworkspacetomonitor 1 DP-1" "keyword monitor eDP-1\\,disable"
assert_not_contains "dispatch dpms"
assert_not_contains "keyword monitor DP-1\\,2560x1440"
assert_no_process_restart
[[ "$(grep -Fc route "${AUDIO_ROUTE_LOG}")" -eq 1 ]]
[[ "$(cat "${BACKLIGHT_VALUE_PATH}")" -eq 0 ]]
[[ "$(cat "${HYPR_LID_BACKLIGHT_STATE_FILE}")" -eq 100 ]]

echo "==> activate dock before disabling internal display"
reset_log
set_monitors "eDP-1 HDMI-A-1" "DP-1 eDP-1 HDMI-A-1"
run_lid closed

assert_contains "keyword monitor DP-1\\,2560x1440@120.01\\,1920x0\\,1"
assert_contains "keyword monitor HDMI-A-1\\,disable"
assert_before "keyword monitor DP-1\\,2560x1440@120.01" "keyword monitor HDMI-A-1\\,disable"
assert_contains "keyword monitor eDP-1\\,disable"
[[ "$(cat "${HYPR_LID_BACKLIGHT_STATE_FILE}")" -eq 100 ]]

echo "==> fail closed transition when dock activation is not observed"
reset_log
rm -f "${MONITOR_ATTEMPTS_PATH}.DP-1"
set_monitors "eDP-1" "DP-1 eDP-1"
if HYPR_MONITOR_FALSE_SUCCESS_ONCE=DP-1 run_lid closed; then
  echo "Expected closed transition to fail when DP-1 stays inactive" >&2
  exit 1
fi

assert_not_contains "moveworkspacetomonitor"

echo "==> open lid while docked"
reset_log
set_monitors "DP-1" "DP-1 eDP-1"
HYPR_ACTIVE_WS=2 run_lid open

assert_contains "keyword monitor eDP-1\\,preferred\\,0x0\\,1"
assert_not_contains "dispatch dpms"
assert_contains "keyword workspace 3\\,monitor:eDP-1\\,persistent:false"
assert_contains "moveworkspacetomonitor 3 eDP-1"
assert_contains "dispatch workspace 2"
assert_not_contains "keyword monitor DP-1\\,2560x1440"
assert_no_process_restart
[[ "$(cat "${BACKLIGHT_VALUE_PATH}")" -eq 100 ]]
[[ ! -e "${HYPR_LID_BACKLIGHT_STATE_FILE}" ]]

echo "==> preserve external focus and allocate dynamic internal workspace"
reset_log
set_monitors "DP-1 eDP-1" "DP-1 eDP-1"
HYPR_WORKSPACES=external123 HYPR_ACTIVE_WS=3 run_lid open

assert_contains "keyword workspace 4\\,monitor:eDP-1\\,persistent:false"
assert_contains "moveworkspacetomonitor 4 eDP-1"
assert_contains "dispatch workspace 3"

echo "==> ignore an empty auto-created internal workspace"
reset_log
set_monitors "DP-1 eDP-1" "DP-1 eDP-1"
HYPR_WORKSPACES=both12auto4 HYPR_ACTIVE_WS=4 HYPR_ACTIVE_MONITOR=eDP-1 run_lid open

assert_contains "keyword workspace 3\\,monitor:eDP-1\\,persistent:false"
assert_contains "keyword workspace 4\\,monitor:DP-1\\,persistent:false"
assert_not_contains "dispatch workspace 4"

echo "==> recover after unplug"
reset_log
printf '2\n' > "${HYPR_LID_ACTIVE_WORKSPACE_FILE}"
set_monitors "eDP-1" "eDP-1"
HYPR_WORKSPACES=internal12auto4 HYPR_ACTIVE_WS=4 HYPR_ACTIVE_MONITOR=eDP-1 run_lid open

assert_not_contains "dispatch dpms"
assert_contains "keyword workspace 1\\,monitor:eDP-1"
assert_not_contains "keyword workspace 3\\,monitor:eDP-1\\,persistent:true"
assert_contains "keyword workspace 4\\,monitor:eDP-1\\,persistent:false"
assert_contains "dispatch workspace 2"
assert_not_contains "dispatch workspace 4"

echo "==> do not reload while DP-1 remains usable"
reset_log
rm -f "${MONITOR_ATTEMPTS_PATH}.eDP-1" "${HYPR_LID_RECOVERY_FILE}"
set_monitors "DP-1" "DP-1 eDP-1"
if HYPR_MONITOR_FALSE_SUCCESS_ONCE=eDP-1 HYPR_RELOAD_RECOVERS=eDP-1 HYPR_LID_RECOVERY_DELAY=0 run_lid open; then exit 1; fi
assert_not_contains "reload"

echo "==> guarded reload when no usable output remains"
reset_log
rm -f "${MONITOR_ATTEMPTS_PATH}.eDP-1" "${HYPR_LID_RECOVERY_FILE}"
set_monitors "" "eDP-1"
HYPR_MONITOR_FALSE_SUCCESS_ONCE=eDP-1 HYPR_RELOAD_RECOVERS=eDP-1 HYPR_LID_RECOVERY_DELAY=0 run_lid open
assert_contains "keyword monitor eDP-1\\,preferred\\,0x0\\,1"
assert_contains "reload"
assert_before "keyword monitor eDP-1\\,preferred" "reload"
assert_contains "keyword workspace 1\\,monitor:eDP-1\\,persistent:false"

echo "==> configure HDMI mirror after enabling internal display"
reset_log
set_monitors "HDMI-A-1" "eDP-1 HDMI-A-1"
HYPR_WORKSPACES=internal12 HYPR_ACTIVE_WS=2 run_lid open

assert_contains "keyword monitor eDP-1\\,preferred\\,0x0\\,1"
assert_contains "keyword monitor HDMI-A-1\\,1920x1080@60\\,0x0\\,1\\,mirror\\,eDP-1"
assert_before "keyword monitor eDP-1\\,preferred" "keyword monitor HDMI-A-1\\,1920x1080@60"
assert_contains "dispatch workspace 2"

if grep -Fq 'kanshi' "${LID_SCRIPT}"; then
  if grep -Eq 'kanshictl|keyword monitor.*kanshi' "${LID_SCRIPT}"; then
    echo "The display transition owner must not delegate outputs to kanshi" >&2
    exit 1
  fi
fi

HYPR_CONFIG="${DOTFILES_DIR}/.config/hypr/hyprland.conf"
if grep -Eq 'exec-once[[:space:]]*=[[:space:]]*kanshi|bindl.*Lid Switch.*lid\.sh' "${HYPR_CONFIG}"; then
  echo "Hyprland must not register another automatic display-transition owner" >&2
  exit 1
fi

if ! grep -Eq '^env[[:space:]]*=[[:space:]]*DE,generic$' "${HYPR_CONFIG}"; then
  echo "Hyprland apps must bypass xdg-utils X11 desktop detection" >&2
  exit 1
fi

echo "OK"
