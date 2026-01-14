#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
SSF_SCRIPT="${SCRIPTS_DIR}/ssf"

if [[ ! -f "${SSF_SCRIPT}" ]]; then
  echo "Missing: ${SSF_SCRIPT}" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

export HOME="${TMPDIR}/home"
mkdir -p "${HOME}/.ssh"

CFG="${HOME}/.ssh/config"
cat > "${CFG}" <<'EOF'
Host cenizas_back_pybackups
  HostName 127.0.0.1
  User boris

Host data
  HostName 192.168.1.184
  User root
EOF

rows="$(bash "${SSF_SCRIPT}" --_rows "${CFG}")"
header_line="$(printf "%s\n" "${rows}" | sed -n '1p')"
row_line="$(printf "%s\n" "${rows}" | sed -n '2p')"

if [[ "${header_line}" != *"Client"* ]] || [[ "${header_line}" != *"Server"* ]] || [[ "${header_line}" != *"IP Address"* ]] || [[ "${header_line}" != *"User"* ]]; then
  echo "Header missing expected columns: ${header_line}" >&2
  exit 1
fi

alias="$(printf "%s" "${row_line}" | cut -f2)"
host="$(printf "%s" "${row_line}" | cut -f3)"
ssh_user="$(printf "%s" "${row_line}" | cut -f4)"

if [[ "${alias}" != "cenizas_back_pybackups" ]]; then
  echo "Unexpected alias: ${alias}" >&2
  exit 1
fi

if [[ "${host}" != "127.0.0.1" ]]; then
  echo "Unexpected host: ${host}" >&2
  exit 1
fi

if [[ "${ssh_user}" != "boris" ]]; then
  echo "Unexpected ssh user: ${ssh_user}" >&2
  exit 1
fi

if [[ "${row_line}" != *"127.0.0.1"* ]]; then
  echo "Expected IP address to appear in display: ${row_line}" >&2
  exit 1
fi

if [[ "${row_line}" != *"boris"* ]]; then
  echo "Expected ssh user to appear in display: ${row_line}" >&2
  exit 1
fi

data_row="$(printf "%s\n" "${rows}" | awk -v needle="\tdata\t" 'index($0, needle) {print; exit}')"
if [[ -z "${data_row}" ]]; then
  echo "Expected to find row for alias 'data'" >&2
  exit 1
fi

display_data="$(printf "%s" "${data_row}" | cut -f1)"
server_col="$(printf "%s" "${display_data}" | sed -E 's/^.{12}  ([^ ]+).*/\1/')"
if [[ "${server_col}" != "data" ]]; then
  echo "Expected single-word host to appear in Server column, got: ${server_col}" >&2
  echo "Row: ${data_row}" >&2
  exit 1
fi

echo "OK"
