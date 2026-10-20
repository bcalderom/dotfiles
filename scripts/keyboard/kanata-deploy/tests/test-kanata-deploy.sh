#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
DOTFILES_DIR="$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)"
DEPLOY_SCRIPT="${SCRIPTS_DIR}/bin/kanata-deploy.sh"

if [[ ! -f "${DEPLOY_SCRIPT}" ]]; then
  echo "Missing: ${DEPLOY_SCRIPT}" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

export HOME="${TMPDIR}/home"
mkdir -p "${HOME}"

DEST_ROOT="${TMPDIR}/root"
mkdir -p "${DEST_ROOT}"
export KANATA_DEST_ROOT="${DEST_ROOT}"
export SUDO=""

MOCK_BIN="${TMPDIR}/bin"
mkdir -p "${MOCK_BIN}"

SYSTEMCTL_LOG="${TMPDIR}/systemctl.log"
: > "${SYSTEMCTL_LOG}"
export SYSTEMCTL_LOG

MODPROBE_LOG="${TMPDIR}/modprobe.log"
: > "${MODPROBE_LOG}"
export MODPROBE_LOG

cat > "${MOCK_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$0" "$@" >> "${SYSTEMCTL_LOG}"
printf '\n' >> "${SYSTEMCTL_LOG}"
exit 0
EOF
chmod +x "${MOCK_BIN}/systemctl"

cat > "${MOCK_BIN}/modprobe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$0" "$@" >> "${MODPROBE_LOG}"
printf '\n' >> "${MODPROBE_LOG}"
exit 0
EOF
chmod +x "${MOCK_BIN}/modprobe"
cat > "${MOCK_BIN}/kanata" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == --check && "$2" == --cfg && -f "$3" ]]
[[ "${MOCK_INVALID_KANATA:-0}" == 0 ]]
EOF
chmod +x "${MOCK_BIN}/kanata"

export PATH="${MOCK_BIN}:${PATH}"

assert_file_exists() {
  local f="$1"
  if [[ ! -f "${f}" ]]; then
    echo "Expected file to exist: ${f}" >&2
    exit 1
  fi
}

assert_mode() {
  local f="$1"
  local expected="$2"
  local got
  got="$(stat -c '%a' "${f}")"
  if [[ "${got}" != "${expected}" ]]; then
    echo "Expected mode ${expected} for ${f}, got ${got}" >&2
    exit 1
  fi
}

echo "==> install"
bash "${DEPLOY_SCRIPT}" --install

assert_file_exists "${DEST_ROOT}/etc/systemd/system/kanata.service"
assert_file_exists "${DEST_ROOT}/etc/kanata/kanata.kbd"
assert_file_exists "${DEST_ROOT}/etc/modules-load.d/uinput.conf"

assert_mode "${DEST_ROOT}/etc/systemd/system/kanata.service" 644
assert_mode "${DEST_ROOT}/etc/kanata/kanata.kbd" 644
assert_mode "${DEST_ROOT}/etc/modules-load.d/uinput.conf" 644

if grep -q -- "dev-uinput.device" "${DEST_ROOT}/etc/systemd/system/kanata.service"; then
  echo "Unexpected dependency on dev-uinput.device in kanata.service" >&2
  exit 1
fi

grep -q -- "uinput" "${DEST_ROOT}/etc/modules-load.d/uinput.conf"

grep -q -- "daemon-reload" "${SYSTEMCTL_LOG}"
grep -q -- "enable --now kanata.service" "${SYSTEMCTL_LOG}"

grep -q -- "uinput" "${MODPROBE_LOG}"

: > "${SYSTEMCTL_LOG}"

echo "==> update"
bash "${DEPLOY_SCRIPT}" --update

grep -q -- "daemon-reload" "${SYSTEMCTL_LOG}"
grep -q -- "restart kanata.service" "${SYSTEMCTL_LOG}"

echo '==> activate validates, enables and restarts exactly once'
: > "${SYSTEMCTL_LOG}"
bash "${DEPLOY_SCRIPT}" --activate
grep -q -- 'enable kanata.service' "${SYSTEMCTL_LOG}"
[[ $(grep -c 'restart kanata.service' "${SYSTEMCTL_LOG}") -eq 1 ]]
if grep -q -- '--now' "${SYSTEMCTL_LOG}"; then exit 1; fi
echo '==> check is read-only and configuration mismatches are incomplete'
: > "${SYSTEMCTL_LOG}"
: > "${MODPROBE_LOG}"
bash "${DEPLOY_SCRIPT}" --check
bash "${DEPLOY_SCRIPT}" --check --activate
if grep -Eq -- 'daemon-reload|enable |restart ' "${SYSTEMCTL_LOG}"; then exit 1; fi
[[ ! -s "${MODPROBE_LOG}" ]]
printf 'different profile\n' > "${DEST_ROOT}/etc/kanata/kanata.kbd"
status=0
bash "${DEPLOY_SCRIPT}" --check >/dev/null || status=$?
[[ $status -eq 1 ]]
echo '==> activation does not overwrite a different user profile'
: > "${SYSTEMCTL_LOG}"
status=0
bash "${DEPLOY_SCRIPT}" --activate >/dev/null 2>&1 || status=$?
[[ $status -eq 2 && ! -s "${SYSTEMCTL_LOG}" ]]
[[ $(cat "${DEST_ROOT}/etc/kanata/kanata.kbd") == 'different profile' ]]
echo '==> invalid source config prevents deployment commands'
: > "${SYSTEMCTL_LOG}"
status=0
MOCK_INVALID_KANATA=1 bash "${DEPLOY_SCRIPT}" --activate || status=$?
[[ $status -ne 0 && ! -s "${SYSTEMCTL_LOG}" ]]

: > "${SYSTEMCTL_LOG}"

echo "==> stow-like symlinks"
DEST_STOW="${TMPDIR}/root-stow"
mkdir -p "${DEST_STOW}/etc/systemd/system" "${DEST_STOW}/etc/kanata" "${DEST_STOW}/etc/modules-load.d"

ln -sf "${DOTFILES_DIR}/.config/systemd/kanata.service" "${DEST_STOW}/etc/systemd/system/kanata.service"
ln -sf "${DOTFILES_DIR}/.config/kanata/kanata.kbd" "${DEST_STOW}/etc/kanata/kanata.kbd"
printf "uinput\n" > "${DEST_STOW}/etc/modules-load.d/uinput.conf"

KANATA_DEST_ROOT="${DEST_STOW}" bash "${DEPLOY_SCRIPT}" --update

if [[ ! -L "${DEST_STOW}/etc/systemd/system/kanata.service" ]]; then
  echo "Expected symlink to remain: /etc/systemd/system/kanata.service" >&2
  exit 1
fi

if [[ ! -L "${DEST_STOW}/etc/kanata/kanata.kbd" ]]; then
  echo "Expected symlink to remain: /etc/kanata/kanata.kbd" >&2
  exit 1
fi

grep -q -- "daemon-reload" "${SYSTEMCTL_LOG}"
grep -q -- "restart kanata.service" "${SYSTEMCTL_LOG}"

echo "OK"
