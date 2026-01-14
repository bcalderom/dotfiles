#!/usr/bin/env bash
set -euo pipefail

MODE="install"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      MODE="install"
      shift
      ;;
    --update)
      MODE="update"
      shift
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--install|--update]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

SVC_SRC="${DOTFILES_DIR}/.config/systemd/user/kanata.service"

SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

SVC_DST="${SYSTEMD_USER_DIR}/kanata.service"

for f in "${SVC_SRC}"; do
  if [[ ! -f "${f}" ]]; then
    echo "Missing: ${f}" >&2
    exit 1
  fi
done

install -d -m 0755 "${SYSTEMD_USER_DIR}"

deploy_file() {
  local src="$1"
  local dst="$2"
  local mode="$3"

  if [[ -e "${dst}" ]] && [[ "$(readlink -f -- "${src}")" == "$(readlink -f -- "${dst}")" ]]; then
    return 0
  fi

  install -m "${mode}" "${src}" "${dst}"
}

deploy_file "${SVC_SRC}" "${SVC_DST}" 0644

if command -v systemctl >/dev/null 2>&1; then
  if systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user daemon-reload
    if [[ "${MODE}" == "install" ]]; then
      echo "Enabling kanata.service..."
      systemctl --user enable --now kanata.service
    else
      echo "Restarting kanata.service..."
      systemctl --user restart kanata.service
    fi

    echo "Status:"
    systemctl --user --no-pager status kanata.service || true
  else
    echo "Warning: systemctl user session not available; skipped daemon-reload/enable" >&2
  fi
else
  echo "Warning: systemctl not found; skipped daemon-reload/enable" >&2
fi

echo "Deployed:"
echo "  ${SVC_DST}"
