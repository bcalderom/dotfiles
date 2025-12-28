#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${HOME}/.config/bt-keyboard"
ENV_SRC="${SRC_DIR}/autoconnect.env"
SVC_SRC="${SRC_DIR}/bt-keyboard.service"

ENV_DST_DIR="/etc/bluetooth"
ENV_DST="${ENV_DST_DIR}/autoconnect.env"
SVC_DST="/etc/systemd/system/bt-keyboard.service"

if [[ ! -f "${ENV_SRC}" ]]; then
  echo "Missing: ${ENV_SRC}"
  exit 1
fi

if [[ ! -f "${SVC_SRC}" ]]; then
  echo "Missing: ${SVC_SRC}"
  exit 1
fi

sudo install -d -m 0755 "${ENV_DST_DIR}" /etc/systemd/system
sudo install -m 0600 "${ENV_SRC}" "${ENV_DST}"
sudo install -m 0644 "${SVC_SRC}" "${SVC_DST}"

sudo systemctl daemon-reload
sudo systemctl enable --now bt-keyboard.service

echo "Deployed:"
echo "  ${ENV_DST}"
echo "  ${SVC_DST}"
echo
echo "Status:"
systemctl --no-pager status bt-keyboard.service || true