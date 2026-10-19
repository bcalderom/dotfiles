#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SETUP="${SCRIPT_DIR}/../../setup.sh"
REAL_STOW="$(command -v stow || true)"
TEMP_BASE="${TMPDIR:-/tmp}"
if [[ -z "${TMPDIR:-}" && -d /tmp/opencode ]]; then TEMP_BASE=/tmp/opencode; fi
WORK="$(mktemp -d "${TEMP_BASE}/setup-test.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/home"
export MOCK_LOG="$WORK/commands.log" MOCK_INSTALLED_FILE="$WORK/installed"
export HOME="$WORK/home"

# Package/service commands are always mocked. The optional real Stow test uses
# only a generated checkout and HOME under WORK, never the actual dotfiles.
cat > "$WORK/bin/pacman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "pacman $*" >> "$MOCK_LOG"
case "$1" in
  -Q)
    grep -Fqx '*' "$MOCK_INSTALLED_FILE" || grep -Fqx -- "$2" "$MOCK_INSTALLED_FILE"
    ;;
  -Si) [[ " ${MOCK_PROMOTED:-} " == *" $2 "* ]] ;;
  -S|-Syu)
    [[ "${MOCK_FAIL_INSTALL:-0}" == 0 ]] || exit 5
    shift
    for package in "$@"; do
      [[ "$package" == -* ]] || echo "$package" >> "$MOCK_INSTALLED_FILE"
    done
    ;;
  *) echo "Unexpected pacman arguments" >&2; exit 99 ;;
esac
EOF
cat > "$WORK/bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "sudo $*" >> "$MOCK_LOG"
exec "$@"
EOF
cat > "$WORK/bin/yay" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$(basename -- "$0") $*" >> "$MOCK_LOG"
[[ "$1" == -S && "$2" == --needed ]] || exit 99
[[ "${MOCK_FAIL_AUR:-0}" == 0 ]] || exit 6
shift 2
printf '%s\n' "$@" >> "$MOCK_INSTALLED_FILE"
EOF
cat > "$WORK/bin/lscpu" <<'EOF'
#!/usr/bin/env bash
printf 'Vendor ID: %s\n' "${MOCK_CPU:-AuthenticAMD}"
EOF
cat > "$WORK/bin/lspci" <<'EOF'
#!/usr/bin/env bash
case "${MOCK_GPU:-amd}" in
  amd) echo '00:01.0 0300: 1002:1234 (rev 01)' ;;
  intel) echo '00:02.0 0300: 8086:1234 (rev 01)' ;;
  nvidia) echo '01:00.0 0302: 10de:1234 (rev 01)' ;;
  hybrid)
    echo '00:02.0 0300: 8086:1234 (rev 01)'
    echo '01:00.0 0300: 1002:1234 (rev 01)' ;;
  none) echo '00:03.0 0200: 8086:1234 (rev 01)' ;;
  *) exit 99 ;;
esac
EOF
cat > "$WORK/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "systemctl $*" >> "$MOCK_LOG"
case "$1" in
  is-enabled) [[ "${MOCK_SERVICE_DISABLED:-0}" == 0 ]] ;;
  enable) exit 0 ;;
  *) echo "Unexpected service action" >&2; exit 99 ;;
esac
EOF
cat > "$WORK/bin/stow" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "stow $*" >> "$MOCK_LOG"
[[ "${MOCK_STOW_CONFLICT:-0}" == 0 ]]
EOF
chmod +x "$WORK/bin/"*
cp "$WORK/bin/yay" "$WORK/bin/paru"
export PATH="$WORK/bin:$PATH"

reset_case() {
  : > "$MOCK_LOG"
  : > "$MOCK_INSTALLED_FILE"
  unset MOCK_CPU MOCK_GPU MOCK_PROMOTED MOCK_FAIL_INSTALL MOCK_FAIL_AUR MOCK_SERVICE_DISABLED MOCK_STOW_CONFLICT
}

run_status() {
  local expected="$1" actual=0
  shift
  bash "$SETUP" "$@" > "$WORK/output" 2>&1 || actual=$?
  if [[ "$actual" -ne "$expected" ]]; then
    cat "$WORK/output" >&2
    echo "Expected status $expected, got $actual for: $*" >&2
    exit 1
  fi
}

contains() { grep -Fq -- "$1" "$WORK/output"; }
not_contains() { ! grep -Fq -- "$1" "$WORK/output"; }
not_line() { ! grep -Fxq -- "$1" "$WORK/output"; }
logged() { grep -Fq -- "$1" "$MOCK_LOG"; }
not_logged() { ! grep -Fq -- "$1" "$MOCK_LOG"; }
read_only() {
  if grep -Eq '^(sudo |pacman -S(yu| )|yay -S|paru -S|systemctl enable|stow --verbose)' "$MOCK_LOG"; then
    cat "$MOCK_LOG" >&2
    echo 'Unexpected mutation in read-only mode' >&2
    exit 1
  fi
}

echo '==> help and argument validation'
reset_case
run_status 0 --help
run_status 0 --list-groups
contains 'amd-gpu intel-gpu'
[[ ! -s "$MOCK_LOG" ]]
for groups in '' 'base,' ,base base,,dev invalid 'base dev' $'base\ndev' "base,\$(touch nope)"; do
  run_status 2 --only "$groups"
done
run_status 2 --with
run_status 2 --cpu invalid
run_status 2 --aur invalid
run_status 2 --only base --cpu amd
run_status 2 --only amd,intel
run_status 2 --unknown
[[ ! -s "$MOCK_LOG" ]]

echo '==> default AMD profile and read-only simulation'
reset_case
run_status 0 --dry-run --stow --enable-services
contains '==> Group: amd'
contains '==> Group: amd-gpu'
contains 'aws-cli-v2'
contains 'opencode'
contains 'rsync'
contains 'sesh-bin brave-bin kanata nordvpn-bin netbird'
not_contains '==> Group: intel'
not_contains '==> Group: docker'
not_contains 'thermald'
not_contains 'yazi'
not_contains '--noconfirm'
read_only

echo '==> CPU and GPU are independent; hybrid and NVIDIA detection'
reset_case
export MOCK_CPU=GenuineIntel MOCK_GPU=hybrid
run_status 0 --dry-run
contains '==> Group: intel'
contains '==> Group: amd-gpu'
contains '==> Group: intel-gpu'
not_line '==> Group: amd'
export MOCK_GPU=nvidia
run_status 0 --dry-run
contains 'NVIDIA detected'
not_contains '==> Group: amd-gpu'
not_contains '==> Group: intel-gpu'
run_status 0 --dry-run --cpu amd --gpu intel
contains '==> Group: amd'
contains '==> Group: intel-gpu'
run_status 0 --dry-run --cpu none --gpu none
not_contains '==> Group: amd'
not_contains '==> Group: intel'
read_only

echo '==> exact groups, opt-ins and AUR-to-repo promotion'
reset_case
run_status 0 --dry-run --only base --with docker,printing,obs,office,comms,media,optional
contains 'docker-compose'
contains 'cups'
contains 'pandoc-cli'
contains 'obs-studio'
contains 'onlyoffice-bin'
not_contains '==> Group: amd'
not_contains '==> Group: dev'
export MOCK_PROMOTED=sesh-bin
run_status 0 --dry-run --only dev
contains 'Missing AUR packages (0):'
contains 'pyenv'
read_only

echo '==> read-only package, service and stow checks'
reset_case
run_status 1 --check --only base
read_only
echo '*' > "$MOCK_INSTALLED_FILE"
run_status 0 --check --stow --enable-services
logged 'stow --simulate'
read_only
export MOCK_STOW_CONFLICT=1
run_status 1 --check --stow
read_only
unset MOCK_STOW_CONFLICT
export MOCK_SERVICE_DISABLED=1
run_status 1 --check --enable-services
contains 'Not enabled: NetworkManager.service'
read_only

echo '==> package installation is repeatable; no implicit confirmations'
reset_case
run_status 0 --only base,base --with base --no-update
logged 'pacman -S --needed zsh'
not_logged --noconfirm
read -r -a installed_command <<< "$(grep '^pacman -S ' "$MOCK_LOG")"
count=0
for word in "${installed_command[@]}"; do
  if [[ "$word" == rsync ]]; then count=$((count + 1)); fi
done
[[ "$count" -eq 1 ]]
: > "$MOCK_LOG"
run_status 0 --only base --no-update
read_only
run_status 0 --only base
logged 'pacman -Syu --needed'
not_logged 'pacman -Sy '

echo '==> failed upgrade prevents later actions'
reset_case
export MOCK_FAIL_INSTALL=1
run_status 5 --only base,network --enable-services
not_logged 'systemctl enable'

echo '==> pending AUR is explicit, helper installs are never run with sudo'
reset_case
run_status 1 --only vpn --no-update
contains 'Setup incomplete'
not_logged 'yay -S'
for helper in yay paru; do
  reset_case
  if [[ $EUID -eq 0 ]]; then
    run_status 2 --only vpn --no-update --aur "$helper"
    [[ ! -s "$MOCK_LOG" ]]
  else
    run_status 0 --only vpn --no-update --aur "$helper"
    logged "$helper -S --needed nordvpn-bin netbird"
    not_logged "sudo $helper"
    not_logged --noconfirm
  fi
done

if [[ $EUID -ne 0 ]]; then
  echo '==> failed AUR build prevents service changes'
  reset_case
  export MOCK_FAIL_AUR=1
  run_status 6 --only network,vpn --no-update --aur yay --enable-services
  not_logged 'systemctl enable'
fi

echo '==> service enable is opt-in and does not start services'
reset_case
echo '*' > "$MOCK_INSTALLED_FILE"
run_status 0 --only network,bluetooth,ui,docker,vpn,printing --no-update --enable-services
logged 'systemctl enable NetworkManager.service systemd-timesyncd.service bluetooth.service power-profiles-daemon.service'
not_logged --now
not_logged 'systemctl enable docker'
not_logged 'systemctl enable sshd'
not_logged 'systemctl enable netbird'
not_logged 'systemctl enable cups'

echo '==> stow conflict prevents linking'
reset_case
echo '*' > "$MOCK_INSTALLED_FILE"
if [[ $EUID -eq 0 ]]; then
  run_status 2 --only base --no-update --stow
else
  export MOCK_STOW_CONFLICT=1
  run_status 1 --only base --no-update --stow
  logged 'stow --simulate'
  not_logged 'stow --verbose'
  unset MOCK_STOW_CONFLICT
  run_status 0 --only base --no-update --stow
  logged 'stow --verbose'
  not_logged --adopt
fi

if [[ -n "$REAL_STOW" && $EUID -ne 0 ]]; then
  echo '==> real Stow: isolated HOME, conflicts, exclusions and repeatability'
  reset_case
  echo '*' > "$MOCK_INSTALLED_FILE"
  fixture="$WORK/stow fixture"
  mkdir -p "$fixture/checkout/.config" "$fixture/checkout/docs" "$fixture/home" "$fixture/bin"
  cp "$SETUP" "$fixture/checkout/setup.sh"
  printf 'managed configuration\n' > "$fixture/checkout/.config/example.conf"
  printf 'managed shell\n' > "$fixture/checkout/.zshrc"
  printf 'documentation\n' > "$fixture/checkout/docs/example.md"
  printf 'existing user shell\n' > "$fixture/home/.zshrc"
  ln -s "$REAL_STOW" "$fixture/bin/stow"
  original_setup="$SETUP"
  SETUP="$fixture/checkout/setup.sh"
  HOME="$fixture/home" PATH="$fixture/bin:$PATH" run_status 1 --only base --no-update --stow
  [[ ! -e "$fixture/home/.config/example.conf" ]]
  [[ "$(cat "$fixture/home/.zshrc")" == 'existing user shell' ]]
  mv "$fixture/home/.zshrc" "$fixture/preserved-zshrc"
  HOME="$fixture/home" PATH="$fixture/bin:$PATH" run_status 0 --only base --no-update --stow
  [[ -L "$fixture/home/.zshrc" && -L "$fixture/home/.config/example.conf" ]]
  [[ ! -e "$fixture/home/setup.sh" && ! -e "$fixture/home/docs" ]]
  HOME="$fixture/home" PATH="$fixture/bin:$PATH" run_status 0 --only base --no-update --stow
  HOME="$fixture/home" PATH="$fixture/bin:$PATH" run_status 0 --only base --check --stow
  echo '==> real Stow: checkout directly inside HOME must not be skipped'
  nested="$WORK/nested home"
  mkdir -p "$nested/dotfiles/.config/systemd/user/graphical-session.target.wants" "$nested/dotfiles/docs"
  cp "$SETUP" "$nested/dotfiles/setup.sh"
  printf 'nested configuration\n' > "$nested/dotfiles/.config/example.conf"
  printf 'nested shell\n' > "$nested/dotfiles/.zshrc"
  printf 'documentation\n' > "$nested/dotfiles/docs/example.md"
  ln -s /usr/lib/systemd/user/example.service "$nested/dotfiles/.config/systemd/user/graphical-session.target.wants/example.service"
  printf 'existing nested shell\n' > "$nested/.zshrc"
  SETUP="$nested/dotfiles/setup.sh"
  HOME="$nested" PATH="$fixture/bin:$PATH" run_status 1 --only base --no-update --stow
  [[ ! -e "$nested/.config/example.conf" ]]
  [[ "$(cat "$nested/.zshrc")" == 'existing nested shell' ]]
  mv "$nested/.zshrc" "$WORK/preserved-nested-zshrc"
  HOME="$nested" PATH="$fixture/bin:$PATH" run_status 0 --only base --no-update --stow
  [[ -L "$nested/.zshrc" && -L "$nested/.config/example.conf" ]]
  [[ ! -e "$nested/setup.sh" && ! -e "$nested/docs" ]]
  [[ ! -e "$nested/.config/systemd/user/graphical-session.target.wants" ]]
  HOME="$nested" PATH="$fixture/bin:$PATH" run_status 0 --only base --no-update --stow
  HOME="$nested" PATH="$fixture/bin:$PATH" run_status 0 --only base --check --stow
  SETUP="$original_setup"
else
  echo '==> real Stow integration skipped (requires Stow and a normal user)'
fi

echo 'OK'
