#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TDS_SCRIPT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)/bin/tds"
tmp_dir="$(mktemp -d)"
launcher="tds-resume-test-$$"
trap 'tmux kill-session -t "$launcher" 2>/dev/null || true; tmux kill-session -t "${launcher}-new" 2>/dev/null || true; tmux kill-session -t oc-resume 2>/dev/null || true; tmux kill-session -t oc-resume-2 2>/dev/null || true; rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/resume"

cat >"$tmp_dir/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$(dirname -- "$0")/opencode-args.log"
tail -f /dev/null
EOF
chmod +x "$tmp_dir/bin/opencode"

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
  [[ "$(tmux show-options -v -t "$name" @opencode_session_id)" == "$id" ]]
  grep -qxF -- '--session' "$log"
  grep -qxF -- "$id" "$log"
  rm -f "$log"
}

tmux new-session -d -s "$launcher" env PATH="$tmp_dir/bin:$PATH" \
  bash -c "\"$TDS_SCRIPT\" --directory \"$tmp_dir/resume\" --layout oc --opencode-session ses_test; exec bash"
assert_session oc-resume ses_test

tmux new-session -d -s "${launcher}-new" env PATH="$tmp_dir/bin:$PATH" \
  bash -c "\"$TDS_SCRIPT\" --directory \"$tmp_dir/resume\" --layout oc --opencode-session ses_new --new-session; exec bash"
assert_session oc-resume-2 ses_new
tmux kill-session -t "${launcher}-new" 2>/dev/null || true
printf 'OK\n'
