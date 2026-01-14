#!/usr/bin/env bash
set -euo pipefail

MODE="install"
SUDO="${SUDO-sudo}"
DEST_ROOT="${KANATA_DEST_ROOT:-/}"

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

SVC_SRC="${DOTFILES_DIR}/.config/systemd/kanata.service"
CFG_SRC="${DOTFILES_DIR}/.config/kanata/kanata.kbd"

ETC_DIR="${DEST_ROOT%/}/etc"
SYSTEMD_SYSTEM_DIR="${ETC_DIR}/systemd/system"
KANATA_ETC_DIR="${ETC_DIR}/kanata"
MODULES_LOAD_DIR="${ETC_DIR}/modules-load.d"

SVC_DST="${SYSTEMD_SYSTEM_DIR}/kanata.service"
CFG_DST="${KANATA_ETC_DIR}/kanata.kbd"
UINPUT_DST="${MODULES_LOAD_DIR}/uinput.conf"

for f in "${SVC_SRC}" "${CFG_SRC}"; do
  if [[ ! -f "${f}" ]]; then
    echo "Missing: ${f}" >&2
    exit 1
  fi
done

${SUDO} install -d -m 0755 "${SYSTEMD_SYSTEM_DIR}" "${KANATA_ETC_DIR}" "${MODULES_LOAD_DIR}"

deploy_file() {
  local src="$1"
  local dst="$2"
  local mode="$3"

  if [[ -e "${dst}" ]] && [[ "$(readlink -f -- "${src}")" == "$(readlink -f -- "${dst}")" ]]; then
    return 0
  fi

  ${SUDO} install -m "${mode}" "${src}" "${dst}"
}

deploy_file "${SVC_SRC}" "${SVC_DST}" 0644
deploy_file "${CFG_SRC}" "${CFG_DST}" 0644

if [[ ! -f "${UINPUT_DST}" ]] || [[ "$(cat -- "${UINPUT_DST}" 2>/dev/null || true)" != "uinput"* ]]; then
  printf "uinput\n" | ${SUDO} tee "${UINPUT_DST}" >/dev/null
  ${SUDO} chmod 0644 "${UINPUT_DST}"
fi

if [[ "${MODE}" == "install" ]] && command -v modprobe >/dev/null 2>&1; then
  ${SUDO} modprobe uinput
fi

if command -v systemctl >/dev/null 2>&1; then
  ${SUDO} systemctl daemon-reload
  if [[ "${MODE}" == "install" ]]; then
    echo "Enabling kanata.service..."
    ${SUDO} systemctl enable --now kanata.service
  else
    echo "Restarting kanata.service..."
    ${SUDO} systemctl restart kanata.service
  fi

  echo "Status:"
  ${SUDO} systemctl --no-pager status kanata.service || true
else
  echo "Warning: systemctl not found; skipped daemon-reload/enable" >&2
fi

echo "Deployed:"
echo "  ${SVC_DST}"
echo "  ${CFG_DST}"
echo "  ${UINPUT_DST}"
