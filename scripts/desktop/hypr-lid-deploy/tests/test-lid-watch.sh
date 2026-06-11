#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)"
WATCH_SCRIPT="${DOTFILES_DIR}/.config/hypr/scripts/lid-watch.sh"

if [[ ! -f "${WATCH_SCRIPT}" ]]; then
  echo "Missing: ${WATCH_SCRIPT}" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

LID_STATE_PATH="${TMPDIR}/lid-state"
HANDLER_LOG="${TMPDIR}/handler.log"
LID_HANDLER="${TMPDIR}/lid-handler"
export LID_STATE_PATH HANDLER_LOG LID_HANDLER

cat > "${LID_HANDLER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

grep -o 'closed\|open' "${LID_STATE_PATH}" >> "${HANDLER_LOG}"
EOF
chmod +x "${LID_HANDLER}"

printf 'state: closed\n' > "${LID_STATE_PATH}"

LID_POLL_INTERVAL=0.05 LID_WATCH_ITERATIONS=20 bash "${WATCH_SCRIPT}" &
watch_pid="$!"

sleep 0.15
printf 'state: open\n' > "${LID_STATE_PATH}"

wait "${watch_pid}"

grep -Fxq closed "${HANDLER_LOG}"
grep -Fxq open "${HANDLER_LOG}"

if [[ "$(grep -Fxc closed "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one closed transition" >&2
  exit 1
fi

if [[ "$(grep -Fxc open "${HANDLER_LOG}")" -ne 1 ]]; then
  echo "Expected one open transition" >&2
  exit 1
fi

echo "OK"
