#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
MENU_SCRIPT="${REPO_DIR}/scripts/tmux/sesh-sessions/sesh-menu"
RECENT_SCRIPT="${REPO_DIR}/scripts/tmux/sesh-sessions/opencode-recent"
VIEW_ACTIONS="${REPO_DIR}/scripts/tmux/sesh-sessions/fzf-view-actions"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"

cat >"$tmp_dir/bin/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${FAKE_TMUX_PANES:-}"
EOF
cat >"$tmp_dir/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${OPENCODE_ARGS_LOG:?}"
printf '%s' "${FAKE_OPENCODE_SESSIONS:-[]}"
EOF
chmod +x "$tmp_dir/bin/tmux" "$tmp_dir/bin/opencode"

json='[
  {"id":"ses_open","title":"Open session","directory":"/tmp/open"},
  {"id":"ses_1","title":"First","directory":"/tmp/one"},
  {"id":"ses_2","title":"Second","directory":"/tmp/two"},
  {"id":"ses_3","title":"Third","directory":"/tmp/three"},
  {"id":"ses_4","title":"Fourth","directory":"/tmp/four"},
  {"id":"ses_5","title":"Fifth","directory":"/tmp/five"},
  {"id":"ses_6","title":"Sixth","directory":"/tmp/six"}
]'

run_recent() {
  FAKE_OPENCODE_SESSIONS="$json" \
    FAKE_TMUX_PANES=$'opencode\tses_open\n' \
    OPENCODE_ARGS_LOG="$tmp_dir/opencode-args.log" \
    OPENCODE_BIN="$tmp_dir/bin/opencode" \
    PATH="$tmp_dir/bin:$PATH" \
    "$@"
}

output="$(run_recent "$RECENT_SCRIPT")"
[[ "$output" != *ses_open* ]]
[[ "$output" == *$'ses_1\tFirst\t/tmp/one'* ]]
[[ "$output" == *$'ses_5\tFifth\t/tmp/five'* ]]
[[ "$output" != *ses_6* ]]
[[ "$(printf '%s\n' "$output" | wc -l)" == 5 ]]
grep -qxF -- '--pure' "$tmp_dir/opencode-args.log"
grep -qxF -- 'db' "$tmp_dir/opencode-args.log"
grep -qF -- 'parent_id is null and time_archived is null' "$tmp_dir/opencode-args.log"
grep -qF -- 'order by time_updated desc' "$tmp_dir/opencode-args.log"

menu_output="$(NO_COLOR=1 run_recent "$MENU_SCRIPT" --list recent)"
[[ "$menu_output" == *$'ses_1\topencode\tsession\t First  /tmp/one\t/tmp/one'* ]]
[[ "$(printf '%s\n' "$menu_output" | wc -l)" == 5 ]]

[[ "$(FZF_WRAP='' "$VIEW_ACTIONS" recent)" == 'change-prompt(recent  )+toggle-wrap-word' ]]
[[ "$(FZF_WRAP=word "$VIEW_ACTIONS" recent)" == 'change-prompt(recent  )' ]]
[[ "$(FZF_WRAP=word "$VIEW_ACTIONS" projects)" == 'change-prompt(projects  )+toggle-wrap-word' ]]
[[ "$(FZF_WRAP='' "$VIEW_ACTIONS" projects)" == 'change-prompt(projects  )' ]]
printf 'OK\n'
