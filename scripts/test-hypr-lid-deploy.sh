#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/hypr-lid-deploy.sh"

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

cat > "${MOCK_BIN}/systemctl" <<EOF
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

assert_file_exists "${HOME}/.config/systemd/user/hypr-lid.service"
assert_file_exists "${HOME}/.config/systemd/user/hypr-lid.path"
assert_file_exists "${HOME}/.config/hypr/scripts/lid.sh"

assert_mode "${HOME}/.config/systemd/user/hypr-lid.service" 644
assert_mode "${HOME}/.config/systemd/user/hypr-lid.path" 644
assert_mode "${HOME}/.config/hypr/scripts/lid.sh" 755

grep -q "--user daemon-reload" "${SYSTEMCTL_LOG}"
grep -q "--user enable --now hypr-lid.path" "${SYSTEMCTL_LOG}"

: > "${SYSTEMCTL_LOG}"

echo "==> update"
bash "${DEPLOY_SCRIPT}" --update

grep -q "--user daemon-reload" "${SYSTEMCTL_LOG}"
grep -q "--user restart hypr-lid.path" "${SYSTEMCTL_LOG}"

: > "${SYSTEMCTL_LOG}"

echo "==> stow-like symlinks"
HOME_STOW="${TMPDIR}/home-stow"
mkdir -p "${HOME_STOW}/.config/systemd/user" "${HOME_STOW}/.config/hypr/scripts"
ln -sf "${SCRIPT_DIR}/../.config/systemd/user/hypr-lid.service" "${HOME_STOW}/.config/systemd/user/hypr-lid.service"
ln -sf "${SCRIPT_DIR}/../.config/systemd/user/hypr-lid.path" "${HOME_STOW}/.config/systemd/user/hypr-lid.path"
ln -sf "${SCRIPT_DIR}/../.config/hypr/scripts/lid.sh" "${HOME_STOW}/.config/hypr/scripts/lid.sh"

HOME="${HOME_STOW}" bash "${DEPLOY_SCRIPT}" --update

if [[ ! -L "${HOME_STOW}/.config/systemd/user/hypr-lid.service" ]]; then
  echo "Expected symlink to remain: hypr-lid.service" >&2
  exit 1
fi

grep -q "--user daemon-reload" "${SYSTEMCTL_LOG}"
grep -q "--user restart hypr-lid.path" "${SYSTEMCTL_LOG}"

echo "OK"
