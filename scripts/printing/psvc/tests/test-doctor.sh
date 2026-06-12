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

cat > "${MOCK_BIN}/lpstat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "-d")
    printf '%s\n' "system default destination: brother_t720dw"
    ;;
  "-p brother_t720dw")
    if [[ "${PSVC_TEST_QUEUE_DISABLED:-0}" -eq 1 ]]; then
      printf '%s\n' "printer brother_t720dw disabled since today"
    else
      printf '%s\n' "printer brother_t720dw is idle. enabled since today"
    fi
    ;;
  "-a brother_t720dw")
    if [[ "${PSVC_TEST_QUEUE_REJECTING:-0}" -eq 1 ]]; then
      printf '%s\n' "brother_t720dw not accepting requests since today"
    else
      printf '%s\n' "brother_t720dw accepting requests since today"
    fi
    ;;
  "-v brother_t720dw")
    printf '%s\n' "device for brother_t720dw: ipp://192.168.1.50/ipp/print"
    ;;
  "-W not-completed -l -o brother_t720dw")
    ;;
  "-W completed -l -o brother_t720dw")
    if [[ "${PSVC_TEST_COMPLETED_PROBLEM:-0}" -eq 1 ]]; then
      printf '%s\n' "brother_t720dw-25       boris            51200   Thu 11 Jun 2026 06:59:27 PM -04"
      printf '%s\n' "\tStatus: Unable to add document to print job."
      printf '%s\n' "\tAlerts: job-completed-successfully"
      printf '%s\n' "\tqueued for brother_t720dw"
    else
      printf '%s\n' "brother_t720dw-25       boris            51200   Thu 11 Jun 2026 06:59:27 PM -04"
      printf '%s\n' "\tStatus:"
      printf '%s\n' "\tAlerts: job-completed-successfully"
      printf '%s\n' "\tqueued for brother_t720dw"
    fi
    ;;
  *)
    printf '%s\n' "unexpected lpstat args: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${MOCK_BIN}/lpstat"

cat > "${MOCK_BIN}/lpq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "brother_t720dw is ready"
printf '%s\n' "no entries"
EOF
chmod +x "${MOCK_BIN}/lpq"

cat > "${MOCK_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  show)
    printf '%s\n' "loaded"
    ;;
  is-active)
    printf '%s\n' "active"
    ;;
  is-enabled)
    printf '%s\n' "disabled"
    ;;
  *)
    printf '%s\n' "unexpected systemctl args: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${MOCK_BIN}/systemctl"

cat > "${MOCK_BIN}/ip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "route get 192.168.1.50")
    printf '%s\n' "192.168.1.50 dev wlan0 src 192.168.1.107"
    ;;
  "neigh show 192.168.1.50")
    printf '%s\n' "192.168.1.50 dev wlan0 lladdr 74:97:79:ba:74:83 REACHABLE"
    ;;
esac
EOF
chmod +x "${MOCK_BIN}/ip"

cat > "${MOCK_BIN}/nc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${PSVC_TEST_NC_FAIL:-0}" -eq 1 ]]; then
  exit 1
fi
if [[ -n "${PSVC_TEST_NC_ATTEMPTS_FILE:-}" ]]; then
  count=0
  if [[ -f "${PSVC_TEST_NC_ATTEMPTS_FILE}" ]]; then
    count="$(<"${PSVC_TEST_NC_ATTEMPTS_FILE}")"
  fi
  count=$((count + 1))
  printf '%s\n' "${count}" > "${PSVC_TEST_NC_ATTEMPTS_FILE}"
  if [[ "${PSVC_TEST_NC_FAIL_FIRST:-0}" -eq 1 && "${count}" -eq 1 ]]; then
    exit 1
  fi
fi
exit 0
EOF
chmod +x "${MOCK_BIN}/nc"

cat > "${MOCK_BIN}/ping" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "${MOCK_BIN}/ping"

cat > "${MOCK_BIN}/ippfind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "ipp://BRW749779BA7483.local:631/ipp/print"
EOF
chmod +x "${MOCK_BIN}/ippfind"

cat > "${MOCK_BIN}/avahi-browse" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "=  wlan0 IPv4 Brother DCP-T720DW Internet Printer local"
printf '%s\n' "   hostname = [BRW749779BA7483.local]"
printf '%s\n' "   address = [192.168.1.50]"
printf '%s\n' "   port = [631]"
printf '%s\n' "Failed to resolve service 'Brother DCP-T720DW' of type '_ipp._tcp' in domain 'local': Timeout reached"
EOF
chmod +x "${MOCK_BIN}/avahi-browse"

cat > "${MOCK_BIN}/getent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 2
EOF
chmod +x "${MOCK_BIN}/getent"

cat > "${MOCK_BIN}/journalctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *avahi-daemon.service*)
    printf '%s\n' "Detected another IPv4 mDNS stack running on this host"
    ;;
  *cups.service*)
    printf '%s\n' "Started CUPS Scheduler"
    ;;
esac
EOF
chmod +x "${MOCK_BIN}/journalctl"

output="$(PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" doctor --queue brother_t720dw)"

if [[ "${output}" != *"[PASS] CUPS queue 'brother_t720dw' exists and is enabled"* ]]; then
  echo "Expected queue readiness pass" >&2
  printf '%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"[PASS] CUPS queue 'brother_t720dw' is accepting requests"* ]]; then
  echo "Expected queue accepting pass" >&2
  printf '%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"[PASS] Recent completed jobs in 'brother_t720dw' have no reported queue errors"* ]]; then
  echo "Expected completed job history pass" >&2
  printf '%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"[PASS] IPP port 631 reachable at 192.168.1.50"* ]]; then
  echo "Expected IPP reachability pass" >&2
  printf '%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"[WARN] mDNS hostname does not resolve through NSS: BRW749779BA7483.local"* ]]; then
  echo "Expected mDNS NSS warning" >&2
  printf '%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"[WARN] Avahi reports another mDNS stack running"* ]]; then
  echo "Expected duplicate mDNS warning" >&2
  printf '%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"[WARN] Avahi discovery returned partial resolution errors"* ]]; then
  echo "Expected Avahi partial resolution warning" >&2
  printf '%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"Failures: 0,"* ]]; then
  echo "Expected no failures" >&2
  printf '%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"Overall: WARN"* ]]; then
  echo "Expected warnings to classify the overall result as WARN" >&2
  printf '%s\n' "${output}" >&2
  exit 1
fi

tolerant_output="$(PSVC_TEST_NC_FAIL=1 PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" doctor --queue brother_t720dw)"
if [[ "${tolerant_output}" != *"[WARN] IPP port 631 is not reachable at 192.168.1.50 after 2 attempts"* ]]; then
  echo "Expected non-strict IPP failure to be a warning" >&2
  printf '%s\n' "${tolerant_output}" >&2
  exit 1
fi
if [[ "${tolerant_output}" != *"Failures: 0,"* ]]; then
  echo "Expected non-strict IPP failure to keep failures at zero" >&2
  printf '%s\n' "${tolerant_output}" >&2
  exit 1
fi

set +e
strict_output="$(PSVC_TEST_NC_FAIL=1 PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" doctor --queue brother_t720dw --strict-network 2>&1)"
strict_rc=$?
set -e
if [[ "${strict_rc}" -eq 0 ]]; then
  echo "Expected strict network failure to exit non-zero" >&2
  printf '%s\n' "${strict_output}" >&2
  exit 1
fi
if [[ "${strict_output}" != *"[FAIL] IPP port 631 is not reachable at 192.168.1.50 after 2 attempts"* ]]; then
  echo "Expected strict IPP failure" >&2
  printf '%s\n' "${strict_output}" >&2
  exit 1
fi
if [[ "${strict_output}" != *"Overall: FAIL"* ]]; then
  echo "Expected failures to classify the overall result as FAIL" >&2
  printf '%s\n' "${strict_output}" >&2
  exit 1
fi

ATTEMPTS_FILE="${TMPDIR}/nc-attempts"
retry_output="$(PSVC_TEST_NC_ATTEMPTS_FILE="${ATTEMPTS_FILE}" PSVC_TEST_NC_FAIL_FIRST=1 PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" doctor --queue brother_t720dw)"
if [[ "${retry_output}" != *"[PASS] IPP port 631 reachable at 192.168.1.50 after retry 2/2"* ]]; then
  echo "Expected IPP retry success" >&2
  printf '%s\n' "${retry_output}" >&2
  exit 1
fi

completed_problem_output="$(PSVC_TEST_COMPLETED_PROBLEM=1 PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" doctor --queue brother_t720dw)"
if [[ "${completed_problem_output}" != *"[WARN] Recent completed jobs in 'brother_t720dw' include device/CUPS problem status"* ]]; then
  echo "Expected completed job problem warning" >&2
  printf '%s\n' "${completed_problem_output}" >&2
  exit 1
fi

set +e
rejecting_output="$(PSVC_TEST_QUEUE_REJECTING=1 PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" doctor --queue brother_t720dw 2>&1)"
rejecting_rc=$?
set -e
if [[ "${rejecting_rc}" -eq 0 ]]; then
  echo "Expected rejecting queue to exit non-zero" >&2
  printf '%s\n' "${rejecting_output}" >&2
  exit 1
fi
if [[ "${rejecting_output}" != *"[FAIL] CUPS queue 'brother_t720dw' is not accepting requests"* ]]; then
  echo "Expected rejecting queue failure" >&2
  printf '%s\n' "${rejecting_output}" >&2
  exit 1
fi

echo "OK"
