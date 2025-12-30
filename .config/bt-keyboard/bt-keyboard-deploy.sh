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

SRC_DIR="${HOME}/.config/bt-keyboard"
ENV_SRC="${SRC_DIR}/autoconnect.env"
SVC_SRC="${SRC_DIR}/bt-keyboard.service"
SLEEP_SRC="${SRC_DIR}/bt-keyboard.system-sleep"

ENV_DST_DIR="/etc/bluetooth"
ENV_DST="${ENV_DST_DIR}/autoconnect.env"
SVC_DST="/etc/systemd/system/bt-keyboard.service"
SLEEP_DST_DIR="/etc/systemd/system-sleep"
SLEEP_DST="${SLEEP_DST_DIR}/bt-keyboard"

if [[ ! -f "${ENV_SRC}" ]]; then
  echo "Missing: ${ENV_SRC}"
  exit 1
fi

if [[ ! -f "${SVC_SRC}" ]]; then
  echo "Missing: ${SVC_SRC}"
  exit 1
fi

if [[ ! -f "${SLEEP_SRC}" ]]; then
  echo "Missing: ${SLEEP_SRC}"
  exit 1
fi

sudo install -d -m 0755 "${ENV_DST_DIR}" /etc/systemd/system "${SLEEP_DST_DIR}"
sudo install -m 0600 "${ENV_SRC}" "${ENV_DST}"
sudo install -m 0644 "${SVC_SRC}" "${SVC_DST}"
sudo install -m 0755 "${SLEEP_SRC}" "${SLEEP_DST}"

sudo systemctl daemon-reload
if [[ "${MODE}" == "install" ]]; then
  echo "Enabling bt-keyboard.service..."
  sudo systemctl enable --now bt-keyboard.service
else
  echo "Restarting bt-keyboard.service..."
  sudo systemctl restart bt-keyboard.service
fi

echo "Deployed:"
echo "  ${ENV_DST}"
echo "  ${SVC_DST}"
echo "  ${SLEEP_DST}"
echo
echo "Status:"
systemctl --no-pager status bt-keyboard.service || true