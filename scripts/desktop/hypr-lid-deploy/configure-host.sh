#!/usr/bin/env bash
# Explicit host-local lid policy. No changes unless --apply is selected.
set -euo pipefail

MODE="${1:---dry-run}"
[[ $# -le 1 ]] || { echo 'Usage: configure-host.sh [--dry-run|--check|--apply]' >&2; exit 2; }
case "$MODE" in --dry-run|--check|--apply) ;; *) echo "Unknown mode: $MODE" >&2; exit 2 ;; esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
SUDO="${SUDO-sudo}"
# Alternate roots are for isolated tests, not for deploying another live host.
DEST_ROOT="${LID_DEST_ROOT:-/}"
PROC_ROOT="${LID_PROC_ROOT:-/proc/acpi/button/lid}"
BACKLIGHT_ROOT="${LID_BACKLIGHT_ROOT:-/sys/class/backlight}"
POLICY_SRC="$SCRIPT_DIR/logind-lid.conf"
POLICY_DST="${DEST_ROOT%/}/etc/systemd/logind.conf.d/60-dotfiles-lid.conf"
HARDWARE_DST="$HOME/.config/systemd/user/hypr-lid.service.d/20-local-hardware.conf"
die() { echo "Lid setup: $*" >&2; exit 2; }

if [[ -z "${LID_STATE_PATH:-}" ]]; then
  sensors=()
  for path in "$PROC_ROOT"/*/state; do [[ ! -r "$path" ]] || sensors+=("$path"); done
  [[ ${#sensors[@]} -eq 1 ]] || die 'Expected one lid sensor; set LID_STATE_PATH explicitly if needed'
  LID_STATE_PATH="${sensors[0]}"
fi
[[ -r "$LID_STATE_PATH" ]] || die 'Lid sensor is not readable'
if [[ -z "${HYPR_LID_BACKLIGHT_DEVICE:-}" ]]; then
  devices=() raw=()
  for path in "$BACKLIGHT_ROOT"/*; do
    [[ -d "$path" ]] || continue
    devices+=("${path##*/}")
    if [[ -r "$path/type" && $(cat "$path/type") == raw ]]; then raw+=("${path##*/}"); fi
  done
  if [[ ${#raw[@]} -eq 1 ]]; then
    HYPR_LID_BACKLIGHT_DEVICE="${raw[0]}"
  elif [[ ${#devices[@]} -eq 1 ]]; then
    HYPR_LID_BACKLIGHT_DEVICE="${devices[0]}"
  else
    die 'Backlight is missing or ambiguous; set HYPR_LID_BACKLIGHT_DEVICE explicitly'
  fi
fi
[[ "$LID_STATE_PATH" =~ ^/[a-zA-Z0-9_./:-]+$ && "$HYPR_LID_BACKLIGHT_DEVICE" =~ ^[a-zA-Z0-9_:-]+$ ]] || die 'Unsafe hardware identifier'
[[ -d "$BACKLIGHT_ROOT/$HYPR_LID_BACKLIGHT_DEVICE" ]] || die 'Selected backlight does not exist'
hardware="$(printf '[Service]\nEnvironment="LID_STATE_PATH=%s"\nEnvironment="HYPR_LID_BACKLIGHT_DEVICE=%s"' "$LID_STATE_PATH" "$HYPR_LID_BACKLIGHT_DEVICE")"
[[ -f "$POLICY_SRC" ]] || die 'Missing logind policy template'

# Do not overwrite user scripts or a different host override without review.
sources=(.config/systemd/user/hypr-lid.service .config/hypr/scripts/lid.sh .config/hypr/scripts/lid-watch.sh)
for relative in "${sources[@]}"; do
  [[ -f "$REPO_DIR/$relative" ]] || die "Missing deployment file: $relative"
  if [[ "$MODE" != --check && ( -e "$HOME/$relative" || -L "$HOME/$relative" ) ]]; then
    cmp -s "$REPO_DIR/$relative" "$HOME/$relative" || die "Existing file differs: $HOME/$relative"
  fi
done
if [[ "$MODE" != --check ]]; then
  if [[ -e "$POLICY_DST" || -L "$POLICY_DST" ]]; then
    if [[ -L "$POLICY_DST" ]] || ! cmp -s "$POLICY_SRC" "$POLICY_DST"; then die 'Existing managed logind drop-in differs'; fi
  fi
  if [[ -e "$HARDWARE_DST" || -L "$HARDWARE_DST" ]]; then
    if [[ -L "$HARDWARE_DST" ]] || [[ $(cat "$HARDWARE_DST") != "$hardware" ]]; then die 'Existing managed hardware override differs'; fi
  fi
  [[ ! -e "$HOME/.config/systemd/user/hypr-lid.path" && ! -L "$HOME/.config/systemd/user/hypr-lid.path" ]] || die 'Review legacy hypr-lid.path before deploying'
fi

echo "Lid sensor: $LID_STATE_PATH; backlight: $HYPR_LID_BACKLIGHT_DEVICE"
echo 'Lid-close policy: stay awake on battery, external power and dock (not safe in a bag).'
if [[ "$MODE" == --dry-run ]]; then
  echo "Would install $POLICY_DST and $HARDWARE_DST"
  echo 'Would reload logind and deploy/enable/restart only hypr-lid.service; no Hyprland restart.'
  exit 0
fi

check_configuration() {
  local incomplete=0 property value relative
  if ! cmp -s "$POLICY_SRC" "$POLICY_DST"; then echo 'Missing/different logind drop-in'; incomplete=1; fi
  if [[ ! -f "$HARDWARE_DST" ]] || [[ $(cat "$HARDWARE_DST") != "$hardware" ]]; then echo 'Missing/different hardware override'; incomplete=1; fi
  for relative in "${sources[@]}"; do
    if ! cmp -s "$REPO_DIR/$relative" "$HOME/$relative"; then echo "Missing/different $relative"; incomplete=1; fi
  done
  for property in HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked; do
    value="$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager "$property" 2>/dev/null || true)"
    if [[ "$value" != 's "ignore"' ]]; then echo "Runtime $property is not ignore"; incomplete=1; fi
  done
  for property in is-enabled is-active; do
    if ! systemctl --user "$property" --quiet hypr-lid.service; then echo "hypr-lid.service is not ${property#is-}"; incomplete=1; fi
  done
  return "$incomplete"
}
if [[ "$MODE" == --check ]]; then check_configuration; exit $?; fi

[[ $EUID -ne 0 ]] || die 'Run as the desktop user, not root'
for program in systemctl busctl hyprctl jq brightnessctl; do command -v "$program" >/dev/null 2>&1 || die "Missing dependency: $program"; done
systemctl --user show-environment >/dev/null || die 'No systemd user session available'
[[ $(systemctl show systemd-logind.service -p CanReload --value) == yes ]] || die 'logind cannot reload safely; no restart will be attempted'
if systemctl --user is-active --quiet hypr-lid.path; then die 'Legacy lid path is active; review it before deploying'; fi
[[ ! -L "${DEST_ROOT%/}/etc/systemd/logind.conf.d" ]] || die 'Linked logind drop-in directory rejected'
[[ ! -L "${HARDWARE_DST%/*}" ]] || die 'Linked hardware drop-in directory rejected'

${SUDO} install -d -m 0755 "${POLICY_DST%/*}"
${SUDO} install -m 0644 "$POLICY_SRC" "$POLICY_DST"
${SUDO} systemctl reload systemd-logind.service
install -d -m 0755 "${HARDWARE_DST%/*}"
temporary="$(mktemp "${HARDWARE_DST%/*}/.hardware.XXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
printf '%s\n' "$hardware" > "$temporary"
chmod 0644 "$temporary"
mv -- "$temporary" "$HARDWARE_DST"
bash "$SCRIPT_DIR/hypr-lid-deploy.sh" --install
check_configuration
echo 'Lid policy and coordinator configured; Hyprland/session/logind were not restarted.'
