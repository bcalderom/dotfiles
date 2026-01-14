#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DOTFILES_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
DEPLOY_SCRIPT="${SCRIPTS_DIR}/kanata-deploy.sh"

if [[ ! -f "${DEPLOY_SCRIPT}" ]]; then
  echo "Missing: ${DEPLOY_SCRIPT}" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

export HOME="${TMPDIR}/home"
mkdir -p "${HOME}"

MOCK_BIN="${TMPDIR}/bin"
mkdir -p "${MOCK_BIN}"

SYSTEMCTL_LOG="${TMPDIR}/systemctl.log"
: > "${SYSTEMCTL_LOG}"
export SYSTEMCTL_LOG

cat > "${MOCK_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$0" "$@" >> "${SYSTEMCTL_LOG}"
printf '\n' >> "${SYSTEMCTL_LOG}"
exit 0
EOF
chmod +x "${MOCK_BIN}/systemctl"

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

assert_file_exists "${HOME}/.config/systemd/user/kanata.service"
assert_mode "${HOME}/.config/systemd/user/kanata.service" 644

grep -q -- "--user daemon-reload" "${SYSTEMCTL_LOG}"
grep -q -- "--user enable --now kanata.service" "${SYSTEMCTL_LOG}"

: > "${SYSTEMCTL_LOG}"

echo "==> update"
bash "${DEPLOY_SCRIPT}" --update

grep -q -- "--user daemon-reload" "${SYSTEMCTL_LOG}"
grep -q -- "--user restart kanata.service" "${SYSTEMCTL_LOG}"

: > "${SYSTEMCTL_LOG}"

echo "==> stow-like symlinks"
HOME_STOW="${TMPDIR}/home-stow"
mkdir -p "${HOME_STOW}/.config/systemd/user"
ln -sf "${DOTFILES_DIR}/.config/systemd/user/kanata.service" "${HOME_STOW}/.config/systemd/user/kanata.service"

HOME="${HOME_STOW}" bash "${DEPLOY_SCRIPT}" --update

if [[ ! -L "${HOME_STOW}/.config/systemd/user/kanata.service" ]]; then
  echo "Expected symlink to remain: kanata.service" >&2
  exit 1
fi

grep -q -- "--user daemon-reload" "${SYSTEMCTL_LOG}"
grep -q -- "--user restart kanata.service" "${SYSTEMCTL_LOG}"

echo "OK"
