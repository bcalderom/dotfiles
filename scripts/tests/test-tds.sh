#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
TDS_SCRIPT="${SCRIPTS_DIR}/tds"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is required for this test" >&2
  exit 1
fi

if [[ ! -f "${TDS_SCRIPT}" ]]; then
  echo "Missing: ${TDS_SCRIPT}" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
SESSION="tds-test-$$"
trap 'tmux kill-session -t "${SESSION}" 2>/dev/null || true; rm -rf "${TMPDIR}"' EXIT

ROOT_DIR="${TMPDIR}/root"
mkdir -p "${ROOT_DIR}"

MOCK_BIN="${TMPDIR}/bin"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${FZF_OUTPUT:-}" ]]; then
  exit 1
fi
printf '%s\n' "${FZF_OUTPUT}"
EOF
chmod +x "${MOCK_BIN}/fzf"

cat > "${MOCK_BIN}/nvim" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
tail -f /dev/null
EOF
chmod +x "${MOCK_BIN}/nvim"

command="\"${TDS_SCRIPT}\" --root \"${ROOT_DIR}\" --depth 0 --debug; exec bash"

tmux new-session -d -s "${SESSION}" env \
  PATH="${MOCK_BIN}:${PATH}" \
  FZF_OUTPUT="${ROOT_DIR}" \
  bash -c "${command}"

sleep 2
pane_count="$(tmux list-panes -t "${SESSION}" | wc -l)"

if [[ "${pane_count}" -ne 3 ]]; then
  echo "Expected 3 panes, got ${pane_count}" >&2
  tmux list-panes -t "${SESSION}" >&2 || true
  tmux capture-pane -p -t "${SESSION}" >&2 || true
  exit 1
fi

echo "OK"
