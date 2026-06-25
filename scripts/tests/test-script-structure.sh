#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

command_dirs=(
  brother/install-brother-t720dw
  desktop/hypr-lid-deploy
  desktop/onn
  desktop/screenshot
  disk/topdisk
  keyboard/kanata-deploy
  network/netbird-audit
  network/sdns
  obs/setup-obs
  packages/yay-cleaner
  printing/psvc
  shell/path
  ssh/ssf
  tmux/sesh-sessions
  tmux/tds
)

bin_links=(
  hypr-lid-deploy.sh
  kanata-deploy.sh
  netbird-audit.sh
  onn
  path
  psvc
  screenshot
  sdns
  ssf
  tds
  topdisk
  yay-cleaner.sh
)

for dir in "${command_dirs[@]}"; do
  if [[ ! -f "${SCRIPTS_DIR}/${dir}/README.md" ]]; then
    echo "Missing README.md in scripts/${dir}" >&2
    exit 1
  fi
done

for link in "${bin_links[@]}"; do
  path="${SCRIPTS_DIR}/bin/${link}"
  if [[ ! -L "${path}" ]]; then
    echo "Expected scripts/bin/${link} to be a symlink" >&2
    exit 1
  fi
  if [[ ! -e "${path}" ]]; then
    echo "Broken symlink: scripts/bin/${link}" >&2
    exit 1
  fi
done

for internal in psvc-doctor psvc-print; do
  if [[ -e "${SCRIPTS_DIR}/bin/${internal}" ]]; then
    echo "Internal helper should not be public: scripts/bin/${internal}" >&2
    exit 1
  fi
done

echo "OK"
