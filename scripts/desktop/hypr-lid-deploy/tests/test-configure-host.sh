#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/../configure-host.sh"
TEMP_BASE="${TMPDIR:-/tmp/opencode}"
[[ -d "$TEMP_BASE" ]] || TEMP_BASE=/tmp
WORK="$(mktemp -d "$TEMP_BASE/lid-host-test.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
export HOME="$WORK/home" LID_DEST_ROOT="$WORK/root" LID_PROC_ROOT="$WORK/proc" LID_BACKLIGHT_ROOT="$WORK/backlight"
export SUDO="" MOCK_LOG="$WORK/commands.log" MOCK_STATE="$WORK/state"
unset LID_STATE_PATH HYPR_LID_BACKLIGHT_DEVICE
mkdir -p "$HOME" "$LID_DEST_ROOT" "$LID_PROC_ROOT/LID" "$LID_BACKLIGHT_ROOT/amdgpu_bl1" "$WORK/bin" "$MOCK_STATE"
printf 'state: open\n' > "$LID_PROC_ROOT/LID/state"
printf 'raw\n' > "$LID_BACKLIGHT_ROOT/amdgpu_bl1/type"
: > "$MOCK_LOG"
cat > "$WORK/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "systemctl $*" >> "$MOCK_LOG"
case "$*" in
  'show systemd-logind.service -p CanReload --value') echo "${MOCK_RELOAD_SUPPORT:-yes}" ;;
  '--user is-active --quiet hypr-lid.path') exit 1 ;;
  '--user is-enabled --quiet hypr-lid.service'|'--user is-active --quiet hypr-lid.service')
    [[ "${MOCK_BAD_SERVICE:-0}" == 0 ]] ;;
esac
EOF
cat > "$WORK/bin/busctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "busctl $*" >> "$MOCK_LOG"
printf 's "%s"\n' "${MOCK_LID_POLICY:-ignore}"
EOF
for program in hyprctl jq brightnessctl; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/$program"
done
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH"
run_status() {
  local expected="$1" actual=0
  shift
  bash "$HELPER" "$@" > "$WORK/output" 2>&1 || actual=$?
  if [[ "$actual" -ne "$expected" ]]; then cat "$WORK/output"; echo "Expected $expected, got $actual" >&2; exit 1; fi
}
policy="$LID_DEST_ROOT/etc/systemd/logind.conf.d/60-dotfiles-lid.conf"
hardware="$HOME/.config/systemd/user/hypr-lid.service.d/20-local-hardware.conf"

echo '==> AMD detection and preview create no files or commands'
run_status 0 --dry-run
grep -Fq 'amdgpu_bl1' "$WORK/output"
grep -Fq "$LID_PROC_ROOT/LID/state" "$WORK/output"
[[ ! -e "$policy" && ! -e "$hardware" && ! -s "$MOCK_LOG" ]]
echo '==> Intel sensor/backlight detection stays compatible'
mv "$LID_PROC_ROOT/LID" "$LID_PROC_ROOT/LID0"
mv "$LID_BACKLIGHT_ROOT/amdgpu_bl1" "$LID_BACKLIGHT_ROOT/intel_backlight"
run_status 0 --dry-run
grep -Fq 'intel_backlight' "$WORK/output"
grep -Fq "$LID_PROC_ROOT/LID0/state" "$WORK/output"
mv "$LID_PROC_ROOT/LID0" "$LID_PROC_ROOT/LID"
mv "$LID_BACKLIGHT_ROOT/intel_backlight" "$LID_BACKLIGHT_ROOT/amdgpu_bl1"

echo '==> absent/ambiguous hardware is rejected; explicit overrides work'
LID_STATE_PATH="$WORK/missing-sensor" run_status 2 --dry-run
HYPR_LID_BACKLIGHT_DEVICE=missing-backlight run_status 2 --dry-run
mkdir -p "$LID_PROC_ROOT/OTHER" "$LID_BACKLIGHT_ROOT/other"
printf 'state: open\n' > "$LID_PROC_ROOT/OTHER/state"
printf 'raw\n' > "$LID_BACKLIGHT_ROOT/other/type"
run_status 2 --dry-run
LID_STATE_PATH="$LID_PROC_ROOT/LID/state" run_status 2 --dry-run
LID_STATE_PATH="$LID_PROC_ROOT/LID/state" HYPR_LID_BACKLIGHT_DEVICE=amdgpu_bl1 run_status 0 --dry-run
mv "$LID_PROC_ROOT/OTHER" "$WORK/other-lid"
mv "$LID_BACKLIGHT_ROOT/other" "$WORK/other-backlight"
echo '==> checks report missing files without changing anything'
run_status 1 --check
[[ ! -e "$policy" && ! -e "$hardware" ]]
if grep -Eq '^systemctl .* (enable|restart|reload|daemon-reload)' "$MOCK_LOG"; then exit 1; fi
if [[ $EUID -eq 0 ]]; then
  run_status 2 --apply
  echo 'Apply fixtures skipped: running as root'
  exit 0
fi

echo '==> apply refuses unsupported reload before writing'
MOCK_RELOAD_SUPPORT=no run_status 2 --apply
[[ ! -e "$policy" && ! -e "$hardware" ]]
echo '==> apply uses fake roots and mocked services only'
: > "$MOCK_LOG"
run_status 0 --apply
cmp -s "$SCRIPT_DIR/../logind-lid.conf" "$policy"
grep -Fq "LID_STATE_PATH=$LID_PROC_ROOT/LID/state" "$hardware"
grep -Fq 'HYPR_LID_BACKLIGHT_DEVICE=amdgpu_bl1' "$hardware"
[[ $(stat -c '%a' "$policy") == 644 && $(stat -c '%a' "$hardware") == 644 ]]
grep -Fxq 'systemctl reload systemd-logind.service' "$MOCK_LOG"
grep -Fxq 'systemctl --user restart hypr-lid.service' "$MOCK_LOG"
if grep -Eq '^systemctl restart systemd-logind|Hyprland' "$MOCK_LOG"; then exit 1; fi

echo '==> reapplication, checks and runtime-policy failures'
run_status 0 --apply
: > "$MOCK_LOG"
run_status 0 --check
if grep -Eq '^systemctl .* (enable|restart|reload|daemon-reload)' "$MOCK_LOG"; then exit 1; fi
MOCK_LID_POLICY=suspend run_status 1 --check
MOCK_BAD_SERVICE=1 run_status 1 --check

echo '==> conflicting user overrides are retained'
printf 'existing user override\n' > "$hardware"
: > "$MOCK_LOG"
run_status 2 --apply
[[ $(cat "$hardware") == 'existing user override' ]]
[[ ! -s "$MOCK_LOG" ]]
echo 'OK'
