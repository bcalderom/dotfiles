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

SVC_SRC="${DOTFILES_DIR}/.config/systemd/user/hypr-lid.service"
PATH_SRC="${DOTFILES_DIR}/.config/systemd/user/hypr-lid.path"
LID_SRC="${DOTFILES_DIR}/.config/hypr/scripts/lid.sh"

SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
HYPR_SCRIPTS_DIR="${HOME}/.config/hypr/scripts"

SVC_DST="${SYSTEMD_USER_DIR}/hypr-lid.service"
PATH_DST="${SYSTEMD_USER_DIR}/hypr-lid.path"
LID_DST="${HYPR_SCRIPTS_DIR}/lid.sh"

for f in "${SVC_SRC}" "${PATH_SRC}" "${LID_SRC}"; do
  if [[ ! -f "${f}" ]]; then
    echo "Missing: ${f}" >&2
    exit 1
  fi
done

install -d -m 0755 "${SYSTEMD_USER_DIR}" "${HYPR_SCRIPTS_DIR}"

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
deploy_file "${PATH_SRC}" "${PATH_DST}" 0644
deploy_file "${LID_SRC}" "${LID_DST}" 0755

if command -v systemctl >/dev/null 2>&1; then
  if systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user daemon-reload
    if [[ "${MODE}" == "install" ]]; then
      echo "Enabling hypr-lid.path..."
      systemctl --user enable --now hypr-lid.path
    else
      echo "Restarting hypr-lid.path..."
      systemctl --user restart hypr-lid.path
    fi

    echo "Status:"
    systemctl --user --no-pager status hypr-lid.path || true
  else
    echo "Warning: systemctl user session not available; skipped daemon-reload/enable" >&2
  fi
else
  echo "Warning: systemctl not found; skipped daemon-reload/enable" >&2
fi

echo "Deployed:"
echo "  ${SVC_DST}"
echo "  ${PATH_DST}"
echo "  ${LID_DST}"
