#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/../yay-cleaner.sh"
TMPDIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

fakebin="${TMPDIR}/bin"
state_home="${TMPDIR}/state"
home_dir="${TMPDIR}/home"
mkdir -p "${fakebin}" "${state_home}" "${home_dir}"

cat >"${fakebin}/du" <<'EOF'
#!/usr/bin/env bash
printf '0\t%s\n' "${!#}"
EOF
chmod +x "${fakebin}/du"

cat >"${fakebin}/yay" <<'EOF'
#!/usr/bin/env bash
touch "${YAY_USED_MARKER}"
exit 99
EOF
chmod +x "${fakebin}/yay"

cat >"${fakebin}/bc" <<'EOF'
#!/usr/bin/env bash
touch "${BC_USED_MARKER}"
exit 99
EOF
chmod +x "${fakebin}/bc"

BC_USED_MARKER="${TMPDIR}/bc-used" \
YAY_USED_MARKER="${TMPDIR}/yay-used" \
PATH="${fakebin}:/usr/bin:/bin" \
XDG_STATE_HOME="${state_home}" \
HOME="${home_dir}" \
  bash "${SCRIPT}"

log_file="${state_home}/yay-cleaner.log"
if [[ ! -s "${log_file}" ]]; then
  echo "Expected user-state log file at ${log_file}" >&2
  exit 1
fi

if [[ -e "${TMPDIR}/bc-used" ]]; then
  echo "yay-cleaner must not require or call bc" >&2
  exit 1
fi

if [[ -e "${TMPDIR}/yay-used" ]]; then
  echo "yay-cleaner should not run yay when caches are below threshold" >&2
  exit 1
fi

if ! grep -q 'below threshold' "${log_file}"; then
  echo "Expected below-threshold message in ${log_file}" >&2
  exit 1
fi

echo "OK"
