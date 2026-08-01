#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
TDS_SCRIPT="${SCRIPTS_DIR}/bin/tds"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is required for this test" >&2
  exit 1
fi

if [[ ! -f "${TDS_SCRIPT}" ]]; then
  echo "Missing: ${TDS_SCRIPT}" >&2
  exit 1
fi

TMPDIR_TEST="$(mktemp -d)"
SESSION="tds-test-$$"

cleanup() {
  tmux kill-session -t "${SESSION}" 2>/dev/null || true
  tmux kill-session -t oc-root 2>/dev/null || true
  tmux kill-session -t oc-root-2 2>/dev/null || true
  tmux kill-session -t oc-deep_target 2>/dev/null || true
  tmux kill-session -t oc-shallow 2>/dev/null || true
  rm -rf "${TMPDIR_TEST}"
}
trap cleanup EXIT

ROOT_DIR="${TMPDIR_TEST}/root"
mkdir -p "${ROOT_DIR}/a/b/c/deep_target" "${ROOT_DIR}/shallow"

MOCK_BIN="${TMPDIR_TEST}/bin"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Turn-based mode: FZF_TURNS lists "key|dir" per invocation, FZF_STATE tracks the turn.
if [[ -n "${FZF_TURNS:-}" ]]; then
  turn=0
  if [[ -f "${FZF_STATE:-}" ]]; then
    turn="$(cat "${FZF_STATE}")"
  fi
  printf '%s\n' "$((turn + 1))" > "${FZF_STATE}"
  line="$(sed -n "$((turn + 1))p" "${FZF_TURNS}")"
  if [[ -z "${line}" ]]; then
    exit 1
  fi
  printf '%s\n%s\n' "${line%%|*}" "${line#*|}"
  exit 0
fi

if [[ -z "${FZF_OUTPUT:-}" ]]; then
  exit 1
fi
printf '\n%s\n' "${FZF_OUTPUT}"
EOF
chmod +x "${MOCK_BIN}/fzf"

cat > "${MOCK_BIN}/nvim" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
tail -f /dev/null
EOF
chmod +x "${MOCK_BIN}/nvim"

cat > "${MOCK_BIN}/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
tail -f /dev/null
EOF
chmod +x "${MOCK_BIN}/opencode"

cat > "${MOCK_BIN}/zoxide" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
query)
  if [[ -n "${ZOXIDE_OUTPUT:-}" ]]; then
    printf '%s\n' "${ZOXIDE_OUTPUT}"
  fi
  ;;
add)
  if [[ -n "${ZOXIDE_ADD_LOG:-}" ]]; then
    printf '%s\n' "${2:-}" >> "${ZOXIDE_ADD_LOG}"
  fi
  ;;
esac
EOF
chmod +x "${MOCK_BIN}/zoxide"

FAILURES=0

fail() {
  echo "FAIL: $*" >&2
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "PASS: $*"
}

test_dirs_initial_respects_depth() {
  local out
  out="$(PATH="${MOCK_BIN}:${PATH}" "${TDS_SCRIPT}" --dirs --root "${ROOT_DIR}" --depth 1)"

  if grep -qxF "${ROOT_DIR}/a" <<< "${out}" && ! grep -qF "deep_target" <<< "${out}"; then
    pass "initial listing respects --depth"
  else
    fail "initial listing should include depth-1 dirs and exclude deep_target; got: ${out}"
  fi
}

test_dirs_query_finds_deep_dirs() {
  local out
  out="$(PATH="${MOCK_BIN}:${PATH}" "${TDS_SCRIPT}" --dirs --root "${ROOT_DIR}" --depth 1 -- deep target)"

  if [[ "${out}" == "${ROOT_DIR}/a/b/c/deep_target" ]]; then
    pass "query finds directories deeper than --depth"
  else
    fail "query should find deep_target; got: ${out}"
  fi
}

test_dirs_zoxide_first_and_deduped() {
  local out
  out="$(PATH="${MOCK_BIN}:${PATH}" ZOXIDE_OUTPUT="${ROOT_DIR}/shallow" \
    "${TDS_SCRIPT}" --dirs --root "${ROOT_DIR}" --depth 1)"

  local first_line
  first_line="$(head -n1 <<< "${out}")"
  local shallow_count
  shallow_count="$(grep -cxF "${ROOT_DIR}/shallow" <<< "${out}")"

  if [[ "${first_line}" == "${ROOT_DIR}/shallow" && "${shallow_count}" -eq 1 ]]; then
    pass "zoxide entries listed first and deduplicated"
  else
    fail "zoxide first/dedup failed; got: ${out}"
  fi
}

test_dirs_no_zoxide_flag() {
  local out
  out="$(PATH="${MOCK_BIN}:${PATH}" ZOXIDE_OUTPUT="${ROOT_DIR}/zoxide_only" \
    "${TDS_SCRIPT}" --dirs --no-zoxide --root "${ROOT_DIR}" --depth 1)"

  local out_query
  out_query="$(PATH="${MOCK_BIN}:${PATH}" ZOXIDE_OUTPUT="${ROOT_DIR}/zoxide_only_shallow" \
    "${TDS_SCRIPT}" --dirs --no-zoxide --root "${ROOT_DIR}" --depth 1 -- shallow)"

  if ! grep -qF "zoxide_only" <<< "${out}" &&
    ! grep -qF "zoxide_only_shallow" <<< "${out_query}" &&
    grep -qxF "${ROOT_DIR}/shallow" <<< "${out_query}"; then
    pass "--no-zoxide omits frecent entries in listing and query"
  else
    fail "--no-zoxide failed; listing: ${out} / query: ${out_query}"
  fi
}

run_layout_flow() {
  local session="$1"
  local command="\"${TDS_SCRIPT}\" --root \"${ROOT_DIR}\" --depth 0 --debug; exec bash"

  tmux new-session -d -s "${session}" env \
    PATH="${MOCK_BIN}:${PATH}" \
    FZF_OUTPUT="${ROOT_DIR}" \
    FZF_TURNS="${FZF_TURNS:-}" \
    FZF_STATE="${TMPDIR_TEST}/fzf-state-${session}" \
    ZOXIDE_ADD_LOG="${TMPDIR_TEST}/zoxide-add.log" \
    bash -c "${command}"
}

wait_for_session() {
  local name="$1"
  local tries=0
  while ((tries < 50)); do
    if tmux has-session -t "${name}" 2>/dev/null; then
      return 0
    fi
    sleep 0.2
    tries=$((tries + 1))
  done
  return 1
}

test_layout_and_session_rename() {
  run_layout_flow "${SESSION}"

  if ! wait_for_session oc-root; then
    fail "session was not renamed to oc-root"
    tmux list-sessions >&2 || true
    return
  fi

  local pane_count
  pane_count="$(tmux list-panes -t oc-root | wc -l)"
  if [[ "${pane_count}" -ne 3 ]]; then
    fail "expected 3 panes, got ${pane_count}"
    tmux list-panes -t oc-root >&2 || true
    return
  fi

  if [[ -f "${TMPDIR_TEST}/zoxide-add.log" ]] &&
    grep -qxF "${ROOT_DIR}" "${TMPDIR_TEST}/zoxide-add.log"; then
    pass "layout applied, session renamed to oc-root, selection recorded in zoxide"
  else
    fail "zoxide add was not called with ${ROOT_DIR}"
  fi
}

test_session_rename_collision() {
  local session2="${SESSION}-collision"
  run_layout_flow "${session2}"

  if wait_for_session oc-root-2; then
    pass "session rename avoids collisions with numeric suffix"
  else
    fail "expected session oc-root-2 on collision"
    tmux list-sessions >&2 || true
  fi

  tmux kill-session -t "${session2}" 2>/dev/null || true
  tmux kill-session -t oc-root-2 2>/dev/null || true
}

test_descend_with_ctrl_d() {
  local turns="${TMPDIR_TEST}/turns-descend"
  printf 'ctrl-d|%s/a\n|%s/a/b/c/deep_target\n' "${ROOT_DIR}" "${ROOT_DIR}" > "${turns}"

  local session="${SESSION}-descend"
  FZF_TURNS="${turns}" run_layout_flow "${session}"

  if wait_for_session oc-deep_target; then
    pass "ctrl-d descends into a directory before selecting"
  else
    fail "expected session oc-deep_target after ctrl-d descend"
    tmux list-sessions >&2 || true
  fi

  tmux kill-session -t "${session}" 2>/dev/null || true
  tmux kill-session -t oc-deep_target 2>/dev/null || true
}

test_ctrl_u_stops_at_base_root() {
  local turns="${TMPDIR_TEST}/turns-up"
  printf 'ctrl-u|%s/a\n|%s/shallow\n' "${ROOT_DIR}" "${ROOT_DIR}" > "${turns}"

  local session="${SESSION}-up"
  FZF_TURNS="${turns}" run_layout_flow "${session}"

  if wait_for_session oc-shallow; then
    pass "ctrl-u at base root keeps the picker working"
  else
    fail "expected session oc-shallow after ctrl-u at base root"
    tmux list-sessions >&2 || true
  fi

  tmux kill-session -t "${session}" 2>/dev/null || true
  tmux kill-session -t oc-shallow 2>/dev/null || true
}

test_dirs_initial_respects_depth
test_dirs_query_finds_deep_dirs
test_dirs_zoxide_first_and_deduped
test_dirs_no_zoxide_flag
test_layout_and_session_rename
test_session_rename_collision
test_descend_with_ctrl_d
test_ctrl_u_stops_at_base_root

if ((FAILURES > 0)); then
  echo "${FAILURES} test(s) failed" >&2
  exit 1
fi

echo "OK"
