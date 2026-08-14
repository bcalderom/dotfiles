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
[[ "${FAKE_TMUX_FAIL:-0}" == 1 ]] && exit 1
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
  {"id":"ses_6","title":"Sixth","directory":"/tmp/six"},
  {"id":"ses_7","title":"Seventh","directory":"/tmp/seven"},
  {"id":"ses_8","title":"Eighth","directory":"/tmp/eight"},
  {"id":"ses_9","title":"Ninth","directory":"/tmp/nine"},
  {"id":"ses_10","title":"Tenth","directory":"/tmp/ten"},
  {"id":"ses_11","title":"Eleventh","directory":"/tmp/eleven"}
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
[[ "$output" == *$'ses_10\tTenth\t/tmp/ten'* ]]
[[ "$output" != *ses_11* ]]
[[ "$(printf '%s\n' "$output" | wc -l)" == 10 ]]
grep -qxF -- '--pure' "$tmp_dir/opencode-args.log"
grep -qxF -- 'db' "$tmp_dir/opencode-args.log"
grep -qF -- 'parent_id is null and time_archived is null' "$tmp_dir/opencode-args.log"
grep -qF -- 'order by time_updated desc' "$tmp_dir/opencode-args.log"

no_tmux_output="$(FAKE_TMUX_FAIL=1 run_recent "$RECENT_SCRIPT")"
[[ "$no_tmux_output" == *$'ses_open\tOpen session\t/tmp/open'* ]]
[[ "$no_tmux_output" != *ses_10* ]]
[[ "$(printf '%s\n' "$no_tmux_output" | wc -l)" == 10 ]]

menu_output="$(NO_COLOR=1 run_recent "$MENU_SCRIPT" --list recent)"
[[ "$menu_output" == *$'ses_1\topencode\tsession\t First  /tmp/one\t/tmp/one'* ]]
[[ "$menu_output" == *$'ses_10\topencode\tsession\t Tenth  /tmp/ten\t/tmp/ten'* ]]
[[ "$(printf '%s\n' "$menu_output" | wc -l)" == 10 ]]

[[ "$(FZF_WRAP='' "$VIEW_ACTIONS" recent)" == 'change-prompt(recent  )+toggle-wrap-word' ]]
[[ "$(FZF_WRAP=word "$VIEW_ACTIONS" recent)" == 'change-prompt(recent  )' ]]
[[ "$(FZF_WRAP=word "$VIEW_ACTIONS" projects)" == 'change-prompt(projects  )+toggle-wrap-word' ]]
[[ "$(FZF_WRAP='' "$VIEW_ACTIONS" projects)" == 'change-prompt(projects  )' ]]
printf 'OK\n'
