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

scp_upload_rel="$(bash "${SSF_SCRIPT}" --_scp_cmd cenizas_back_pybackups upload "./local file.txt" "docs/report.txt")"
if [[ "${scp_upload_rel}" != *"scp"*"-r"*"--"* ]]; then
  echo "Expected scp upload command to include scp -r --, got: ${scp_upload_rel}" >&2
  exit 1
fi
if [[ "${scp_upload_rel}" != *"cenizas_back_pybackups:\~/docs/report.txt"* ]]; then
  echo "Expected remote path to be expanded to ~/ for relative path (shell-escaped), got: ${scp_upload_rel}" >&2
  exit 1
fi

scp_download_abs="$(bash "${SSF_SCRIPT}" --_scp_cmd cenizas_back_pybackups download "./dest" "/var/log/syslog")"
if [[ "${scp_download_abs}" != *"cenizas_back_pybackups:/var/log/syslog"* ]]; then
  echo "Expected absolute remote path to be preserved for download, got: ${scp_download_abs}" >&2
  exit 1
fi

rsync_upload_rel="$(bash "${SSF_SCRIPT}" --_rsync_cmd cenizas_back_pybackups upload "./localdir" "backups")"
if [[ "${rsync_upload_rel}" != *"rsync"*"-avz"*"--progress"*"--"* ]]; then
  echo "Expected rsync upload command to include rsync -avz --progress --, got: ${rsync_upload_rel}" >&2
  exit 1
fi
if [[ "${rsync_upload_rel}" != *"cenizas_back_pybackups:\~/backups"* ]]; then
  echo "Expected remote path to be expanded to ~/ for rsync upload (shell-escaped), got: ${rsync_upload_rel}" >&2
  exit 1
fi

rsync_download_abs="$(bash "${SSF_SCRIPT}" --_rsync_cmd cenizas_back_pybackups download "./dest" "/etc/hosts")"
if [[ "${rsync_download_abs}" != *"cenizas_back_pybackups:/etc/hosts"* ]]; then
  echo "Expected absolute remote path to be preserved for rsync download, got: ${rsync_download_abs}" >&2
  exit 1
fi

scp_download_local_tilde="$(bash "${SSF_SCRIPT}" --_scp_cmd cenizas_back_pybackups download "~/Desarrollos/mysql-backups-s3/" "/tmp/profile.out")"
if [[ "${scp_download_local_tilde}" != *"${HOME}"*"Desarrollos/mysql-backups-s3/"* ]]; then
  echo "Expected local ~ path to be expanded to HOME for scp download, got: ${scp_download_local_tilde}" >&2
  exit 1
fi

rsync_upload_local_tilde="$(bash "${SSF_SCRIPT}" --_rsync_cmd cenizas_back_pybackups upload "~/some dir" "backups")"
if [[ "${rsync_upload_local_tilde}" != *"${HOME}"*"some\ dir"* ]]; then
  echo "Expected local ~ path to be expanded to HOME for rsync upload, got: ${rsync_upload_local_tilde}" >&2
  exit 1
fi

FAKE_BIN="${TMPDIR}/bin"
mkdir -p "${FAKE_BIN}"

cat > "${FAKE_BIN}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${SSF_TEST_SSH_ARGS_FILE:-}" ]]; then
  printf '%s\n' "$*" > "${SSF_TEST_SSH_ARGS_FILE}"
fi
printf '%s\n' "line one"
printf '%s\n' "line two"
EOF
chmod +x "${FAKE_BIN}/ssh"

CLIP_FILE="${TMPDIR}/clipboard.txt"
SSH_ARGS_FILE="${TMPDIR}/ssh-args.txt"
cat > "${FAKE_BIN}/wl-copy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat > "${SSF_TEST_CLIP_FILE}"
EOF
chmod +x "${FAKE_BIN}/wl-copy"

copy_output="$({
  PATH="${FAKE_BIN}:${PATH}" SSF_TEST_CLIP_FILE="${CLIP_FILE}" SSF_TEST_SSH_ARGS_FILE="${SSH_ARGS_FILE}" bash "${SSF_SCRIPT}" --_copy_remote_stdout cenizas_back_pybackups "sudo crontab -l -u wisemin"
} 2>&1)"

if [[ "${copy_output}" != *"Copied stdout from remote command on cenizas_back_pybackups"* ]]; then
  echo "Expected copy_remote_stdout success message, got: ${copy_output}" >&2
  exit 1
fi
if [[ "${copy_output}" != *"Interactive sudo detected; enter remote password if prompted."* ]]; then
  echo "Expected interactive sudo notice, got: ${copy_output}" >&2
  exit 1
fi

ssh_args="$(cat "${SSH_ARGS_FILE}")"
if [[ "${ssh_args}" != *"-tt"* ]]; then
  echo "Expected sudo command to use ssh -tt, got: ${ssh_args}" >&2
  exit 1
fi

clipboard_contents="$(cat "${CLIP_FILE}")"
expected_clipboard=$'line one\nline two'
if [[ "${clipboard_contents}" != "${expected_clipboard}" ]]; then
  echo "Expected clipboard contents to match remote stdout" >&2
  printf 'Got:\n%s\n' "${clipboard_contents}" >&2
  exit 1
fi

copy_output_no_sudo="$({
  PATH="${FAKE_BIN}:${PATH}" SSF_TEST_CLIP_FILE="${CLIP_FILE}" SSF_TEST_SSH_ARGS_FILE="${SSH_ARGS_FILE}" bash "${SSF_SCRIPT}" --_copy_remote_stdout cenizas_back_pybackups "crontab -l -u wisemin"
} 2>&1)"

if [[ "${copy_output_no_sudo}" != *"Copied stdout from remote command on cenizas_back_pybackups"* ]]; then
  echo "Expected copy_remote_stdout success message for non-sudo command, got: ${copy_output_no_sudo}" >&2
  exit 1
fi

ssh_args_no_sudo="$(cat "${SSH_ARGS_FILE}")"
if [[ "${ssh_args_no_sudo}" == *"-tt"* ]]; then
  echo "Expected non-sudo command to avoid ssh -tt, got: ${ssh_args_no_sudo}" >&2
  exit 1
fi

echo "OK"
