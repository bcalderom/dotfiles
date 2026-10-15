#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TDS_SCRIPT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)/bin/tds"
tmp_dir="$(mktemp -d)"
launcher="tds-resume-test-$$"
tmux_bin="$(command -v tmux)"
socket="tds-resume-test-$$"
trap '"$tmux_bin" -L "$socket" kill-server 2>/dev/null || true; rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/resume"

export TDS_TEST_TMUX_BIN="$tmux_bin" TDS_TEST_SOCKET="$socket"
export TDS_TEST_TMUX_LOG="$tmp_dir/tmux.log"
cat >"$tmp_dir/bin/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TDS_TEST_TMUX_LOG"
exec "$TDS_TEST_TMUX_BIN" -L "$TDS_TEST_SOCKET" -f /dev/null "$@"
EOF
chmod +x "$tmp_dir/bin/tmux"
export PATH="$tmp_dir/bin:$PATH" SHELL=/bin/bash

cat >"$tmp_dir/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$(dirname -- "$0")/opencode-args.log"
printf '%s\n' "$PWD" >"$(dirname -- "$0")/opencode-cwd.log"
tail -f /dev/null
EOF
chmod +x "$tmp_dir/bin/opencode"
cat >"$tmp_dir/bin/zoxide" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp_dir/bin/zoxide"

wait_for() {
  local name="$1"
  for _ in {1..50}; do
    tmux has-session -t "$name" 2>/dev/null && return
    sleep 0.1
  done
  return 1
}

assert_session() {
  local name="$1"
  local id="$2"
  local log="$tmp_dir/bin/opencode-args.log"
  wait_for "$name"
  for _ in {1..50}; do
    [[ -f "$log" ]] && break
    sleep 0.1
  done
  if [[ ! -f "$log" ]]; then
    printf 'OpenCode did not start in %s\n' "$name" >&2
    tmux capture-pane -p -t "$name" >&2
    tmux capture-pane -p -t "${launcher}-new" >&2 || true
    exit 1
  fi
  [[ "$(tmux show-options -v -t "$name" @opencode_session_id)" == "$id" ]]
  grep -qxF -- '--session' "$log"
  grep -qxF -- "$id" "$log"
  [[ "$(cat "$tmp_dir/bin/opencode-cwd.log")" == "$tmp_dir/resume" ]]
  rm -f "$log"
}

tmux new-session -d -s "$launcher" env PATH="$tmp_dir/bin:$PATH" \
  bash -c "\"$TDS_SCRIPT\" --directory \"$tmp_dir/resume\" --layout oc --opencode-session ses_test; exec bash"
assert_session oc-resume ses_test

: >"$TDS_TEST_TMUX_LOG"
tmux new-session -d -s "${launcher}-new" env PATH="$tmp_dir/bin:$PATH" \
  bash -c "\"$TDS_SCRIPT\" --directory \"$tmp_dir/resume\" --layout oc --opencode-session ses_new --new-session; exec bash"
assert_session oc-resume-2 ses_new
if grep -E '^send-keys .*cd --|^send-keys .*--layout' "$TDS_TEST_TMUX_LOG"; then
  printf 'New sessions must not queue cd or restart tds\n' >&2
  exit 1
fi
tmux kill-session -t "${launcher}-new" 2>/dev/null || true
printf 'OK\n'
