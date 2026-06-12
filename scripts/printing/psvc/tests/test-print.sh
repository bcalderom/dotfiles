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

cat > "${MOCK_BIN}/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
input="$(mktemp)"
trap 'rm -f "${input}"' EXIT
cat > "${input}"

if [[ -n "${FZF_EXPECTED_INPUT:-}" ]]; then
  while IFS= read -r expected; do
    [[ -n "${expected}" ]] || continue
    if ! grep -Fx -- "${expected}" "${input}" >/dev/null; then
      echo "Expected fzf input to contain: ${expected}" >&2
      cat "${input}" >&2
      exit 1
    fi
  done <<< "${FZF_EXPECTED_INPUT}"
fi

if [[ -n "${FZF_FORBIDDEN_INPUT:-}" ]]; then
  while IFS= read -r forbidden; do
    [[ -n "${forbidden}" ]] || continue
    if grep -Fx -- "${forbidden}" "${input}" >/dev/null; then
      echo "Expected fzf input not to contain: ${forbidden}" >&2
      cat "${input}" >&2
      exit 1
    fi
  done <<< "${FZF_FORBIDDEN_INPUT}"
fi

[[ -n "${FZF_OUTPUT:-}" ]] || exit 1
printf '%s\n' "${FZF_OUTPUT}"
EOF
chmod +x "${MOCK_BIN}/fzf"

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

HOME_DIR="${TMPDIR}/home"
mkdir -p "${HOME_DIR}/Documents" "${HOME_DIR}/.cache"
FZF_DOC="${HOME_DIR}/Documents/fzf-doc.txt"
FZF_IMAGE="${HOME_DIR}/Documents/image.png"
FZF_OFFICE_DOC="${HOME_DIR}/Documents/office.docx"
FZF_HIDDEN_DOC="${HOME_DIR}/.cache/hidden.pdf"
printf '%s\n' "print me" > "${FZF_DOC}"
printf '%s\n' "not a selectable document" > "${FZF_IMAGE}"
printf '%s\n' "not directly printable" > "${FZF_OFFICE_DOC}"
printf '%s\n' "%PDF-1.4" > "${FZF_HIDDEN_DOC}"

: > "${LP_LOG}"
printf '1\ny\n' | \
  FZF_OUTPUT="${FZF_DOC}" \
  FZF_EXPECTED_INPUT="${FZF_DOC}" \
  FZF_FORBIDDEN_INPUT="${FZF_IMAGE}"$'\n'"${FZF_OFFICE_DOC}"$'\n'"${FZF_HIDDEN_DOC}" \
  HOME="${HOME_DIR}" \
  PATH="${MOCK_BIN}:${PATH}" \
  bash "${PSVC_SCRIPT}" print >/dev/null
interactive_lp_args="$(<"${LP_LOG}")"

for expected in "-d" "brother_t720dw" "number-up=2" "sides=two-sided-short-edge" "${FZF_DOC}"; do
  if [[ "${interactive_lp_args}" != *"${expected}"* ]]; then
    echo "Expected interactive lp args to contain: ${expected}" >&2
    printf '%s\n' "${interactive_lp_args}" >&2
    exit 1
  fi
done

: > "${LP_LOG}"
set +e
cancel_output="$(HOME="${HOME_DIR}" PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" print 2>&1 </dev/null)"
cancel_rc=$?
set -e
if [[ "${cancel_rc}" -eq 0 ]]; then
  echo "Expected fzf cancellation to fail" >&2
  printf '%s\n' "${cancel_output}" >&2
  exit 1
fi
if [[ "${cancel_output}" != *"No file selected"* ]]; then
  echo "Expected fzf cancellation to report no selected file" >&2
  printf '%s\n' "${cancel_output}" >&2
  exit 1
fi
if [[ -s "${LP_LOG}" ]]; then
  echo "Canceled fzf selection should not call lp" >&2
  exit 1
fi

: > "${LP_LOG}"
set +e
office_output="$(PATH="${MOCK_BIN}:${PATH}" bash "${PSVC_SCRIPT}" print --yes --preset 2up-short-edge "${FZF_OFFICE_DOC}" 2>&1)"
office_rc=$?
set -e
if [[ "${office_rc}" -eq 0 ]]; then
  echo "Expected Office document printing to fail" >&2
  printf '%s\n' "${office_output}" >&2
  exit 1
fi
if [[ "${office_output}" != *"Export or convert it to PDF first"* ]]; then
  echo "Expected Office document failure to recommend PDF conversion" >&2
  printf '%s\n' "${office_output}" >&2
  exit 1
fi
if [[ -s "${LP_LOG}" ]]; then
  echo "Unsupported Office document should not call lp" >&2
  exit 1
fi

echo "OK"
