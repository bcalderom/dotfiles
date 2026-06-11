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
LP_LOG="${TMPDIR}/lp.log"
: > "${LP_LOG}"
export LP_LOG

cat > "${MOCK_BIN}/lpstat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "-d") printf '%s\n' "system default destination: brother_t720dw" ;;
  "-p brother_t720dw") printf '%s\n' "printer brother_t720dw is idle. enabled since today" ;;
  *) printf '%s\n' "unexpected lpstat args: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "${MOCK_BIN}/lpstat"

cat > "${MOCK_BIN}/lp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" > "${LP_LOG}"
printf '\n' >> "${LP_LOG}"
printf '%s\n' "request id is brother_t720dw-99 (1 file(s))"
EOF
chmod +x "${MOCK_BIN}/lp"

DOC="${TMPDIR}/doc.pdf"
printf '%s\n' "%PDF-1.4" > "${DOC}"

dry_output="$(PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" print --dry-run --preset 2up-short-edge "${DOC}")"

for expected in "lp" "-d" "brother_t720dw" "media=Letter" "number-up=2" "number-up-layout=lrtb" "sides=two-sided-short-edge" "Duplex=DuplexTumble" "fit-to-page" "${DOC}"; do
  if [[ "${dry_output}" != *"${expected}"* ]]; then
    echo "Expected dry-run output to contain: ${expected}" >&2
    printf '%s\n' "${dry_output}" >&2
    exit 1
  fi
done

if [[ -s "${LP_LOG}" ]]; then
  echo "Dry-run should not call lp" >&2
  exit 1
fi

PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" print --yes --preset 2up-short-edge "${DOC}" >/dev/null
lp_args="$(<"${LP_LOG}")"

for expected in "-d" "brother_t720dw" "-o" "media=Letter" "number-up=2" "sides=two-sided-short-edge" "Duplex=DuplexTumble" "fit-to-page" "${DOC}"; do
  if [[ "${lp_args}" != *"${expected}"* ]]; then
    echo "Expected lp args to contain: ${expected}" >&2
    printf '%s\n' "${lp_args}" >&2
    exit 1
  fi
done

echo "OK"
