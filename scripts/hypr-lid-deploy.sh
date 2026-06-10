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
LID_SRC="${DOTFILES_DIR}/.config/hypr/scripts/lid.sh"
WATCH_SRC="${DOTFILES_DIR}/.config/hypr/scripts/lid-watch.sh"

SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
HYPR_SCRIPTS_DIR="${HOME}/.config/hypr/scripts"

SVC_DST="${SYSTEMD_USER_DIR}/hypr-lid.service"
LID_DST="${HYPR_SCRIPTS_DIR}/lid.sh"
WATCH_DST="${HYPR_SCRIPTS_DIR}/lid-watch.sh"
OLD_PATH_DST="${SYSTEMD_USER_DIR}/hypr-lid.path"

for f in "${SVC_SRC}" "${LID_SRC}" "${WATCH_SRC}"; do
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
deploy_file "${LID_SRC}" "${LID_DST}" 0755
deploy_file "${WATCH_SRC}" "${WATCH_DST}" 0755

if command -v systemctl >/dev/null 2>&1; then
  if systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user disable --now hypr-lid.path >/dev/null 2>&1 || true
    rm -f "${OLD_PATH_DST}"
    systemctl --user daemon-reload
    systemctl --user enable hypr-lid.service
    if [[ "${MODE}" == "install" ]]; then
      echo "Starting hypr-lid.service..."
      systemctl --user restart hypr-lid.service
    else
      echo "Restarting hypr-lid.service..."
      systemctl --user restart hypr-lid.service
    fi

    echo "Status:"
    systemctl --user --no-pager status hypr-lid.service || true
  else
    echo "Warning: systemctl user session not available; skipped daemon-reload/enable" >&2
  fi
else
  echo "Warning: systemctl not found; skipped daemon-reload/enable" >&2
fi

echo "Deployed:"
echo "  ${SVC_DST}"
echo "  ${LID_DST}"
echo "  ${WATCH_DST}"
