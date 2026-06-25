#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
PSVC_SCRIPT="${SCRIPTS_DIR}/bin/psvc"

if [[ ! -f "${PSVC_SCRIPT}" ]]; then
  echo "Missing: ${PSVC_SCRIPT}" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

MOCK_BIN="${TMPDIR}/bin"
mkdir -p "${MOCK_BIN}"
SYSTEMCTL_LOG="${TMPDIR}/systemctl.log"
SUDO_LOG="${TMPDIR}/sudo.log"
: > "${SYSTEMCTL_LOG}"
: > "${SUDO_LOG}"
export SYSTEMCTL_LOG SUDO_LOG

cat > "${MOCK_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >> "${SYSTEMCTL_LOG}"
printf '\n' >> "${SYSTEMCTL_LOG}"
case "$1" in
  show) printf '%s\n' "LoadState=loaded" ;;
  status) printf '%s\n' "status ok" ;;
  start|stop|restart|enable|disable) ;;
  *) printf '%s\n' "unexpected systemctl args: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "${MOCK_BIN}/systemctl"

cat > "${MOCK_BIN}/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >> "${SUDO_LOG}"
printf '\n' >> "${SUDO_LOG}"
exec "$@"
EOF
chmod +x "${MOCK_BIN}/sudo"

PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" status >/dev/null
if ! grep -q -- "status --no-pager cups.service" "${SYSTEMCTL_LOG}"; then
  echo "Expected status to check cups.service" >&2
  exit 1
fi
if ! grep -q -- "status --no-pager avahi-daemon.service" "${SYSTEMCTL_LOG}"; then
  echo "Expected status to check avahi-daemon.service" >&2
  exit 1
fi

: > "${SYSTEMCTL_LOG}"
PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" start >/dev/null
if ! grep -q -- "systemctl start cups.service avahi-daemon.service" "${SUDO_LOG}"; then
  echo "Expected start to run through sudo systemctl" >&2
  cat "${SUDO_LOG}" >&2
  exit 1
fi

echo "OK"
