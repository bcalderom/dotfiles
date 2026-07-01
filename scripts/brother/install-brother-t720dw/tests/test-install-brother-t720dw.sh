#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/../install_brother_t720dw.py"

if [[ ! -f "${SCRIPT}" ]]; then
  echo "Missing: ${SCRIPT}" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

MOCK_BIN="${TMPDIR}/bin"
mkdir -p "${MOCK_BIN}"

PACMAN_LOG="${TMPDIR}/pacman.log"
SYSTEMCTL_LOG="${TMPDIR}/systemctl.log"
LPADMIN_LOG="${TMPDIR}/lpadmin.log"
LPOPTIONS_LOG="${TMPDIR}/lpoptions.log"
LPSTAT_LOG="${TMPDIR}/lpstat.log"
LP_CALLED="${TMPDIR}/lp-called"
: > "${PACMAN_LOG}"
: > "${SYSTEMCTL_LOG}"
: > "${LPADMIN_LOG}"
: > "${LPOPTIONS_LOG}"
: > "${LPSTAT_LOG}"

export PACMAN_LOG SYSTEMCTL_LOG LPADMIN_LOG LPOPTIONS_LOG LPSTAT_LOG LP_CALLED

cat > "${MOCK_BIN}/pacman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$0" "$@" >> "${PACMAN_LOG}"
printf '\n' >> "${PACMAN_LOG}"

case "${1:-}" in
  -Q|-S)
    exit 0
    ;;
esac

echo "Unexpected pacman args: $*" >&2
exit 1
EOF
chmod +x "${MOCK_BIN}/pacman"

cat > "${MOCK_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$0" "$@" >> "${SYSTEMCTL_LOG}"
printf '\n' >> "${SYSTEMCTL_LOG}"

if [[ " $* " == *" enable "* ]]; then
  echo "Installers must not enable services" >&2
  exit 1
fi

if [[ "${1:-}" == "start" ]]; then
  exit 0
fi

echo "Unexpected systemctl args: $*" >&2
exit 1
EOF
chmod +x "${MOCK_BIN}/systemctl"

cat > "${MOCK_BIN}/ip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "${MOCK_BIN}/ip"

cat > "${MOCK_BIN}/lpadmin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$0" "$@" >> "${LPADMIN_LOG}"
printf '\n' >> "${LPADMIN_LOG}"

case "$*" in
  "-x brother_t720dw")
    exit 0
    ;;
  "-p brother_t720dw -E -v ipp://192.168.1.50/ipp/print -m everywhere")
    exit 0
    ;;
esac

echo "Unexpected lpadmin args: $*" >&2
exit 1
EOF
chmod +x "${MOCK_BIN}/lpadmin"

cat > "${MOCK_BIN}/lpoptions" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$0" "$@" >> "${LPOPTIONS_LOG}"
printf '\n' >> "${LPOPTIONS_LOG}"
exit 0
EOF
chmod +x "${MOCK_BIN}/lpoptions"

cat > "${MOCK_BIN}/lpstat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$0" "$@" >> "${LPSTAT_LOG}"
printf '\n' >> "${LPSTAT_LOG}"
exit 0
EOF
chmod +x "${MOCK_BIN}/lpstat"

cat > "${MOCK_BIN}/lp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
touch "${LP_CALLED}"
exit 0
EOF
chmod +x "${MOCK_BIN}/lp"

PATH="${MOCK_BIN}:${PATH}" SUDO="" \
  python "${SCRIPT}" --ip 192.168.1.50 --skip-scanner --skip-test-print >/dev/null

grep -q -- "-S --needed --noconfirm cups cups-filters ghostscript avahi nss-mdns" "${PACMAN_LOG}"
grep -q -- "start cups.service avahi-daemon.service" "${SYSTEMCTL_LOG}"
grep -q -- "-p brother_t720dw -E -v ipp://192.168.1.50/ipp/print -m everywhere" "${LPADMIN_LOG}"
grep -q -- "-d brother_t720dw" "${LPOPTIONS_LOG}"
grep -q -- "-t" "${LPSTAT_LOG}"

if grep -q -- "enable" "${SYSTEMCTL_LOG}"; then
  echo "Did not expect service enable" >&2
  exit 1
fi

if [[ -e "${LP_CALLED}" ]]; then
  echo "Did not expect test print when --skip-test-print is set" >&2
  exit 1
fi

echo "OK"
