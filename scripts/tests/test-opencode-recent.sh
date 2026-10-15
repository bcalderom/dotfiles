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
set -euo pipefail
[[ "$1" == api && "$2" == session.list ]]
printf '%s\n' call "$@" >>"${OPENCODE_ARGS_LOG:?}"
[[ "${FAKE_OPENCODE_FAIL:-0}" == 0 ]] || { printf 'API unavailable\n' >&2; exit 1; }
for arg in "$@"; do
  if [[ "$arg" == cursor=next-page ]]; then
    [[ "${FAKE_OPENCODE_NEXT_FAIL:-0}" == 0 ]] || { printf 'Next page unavailable\n' >&2; exit 1; }
    printf '%s' "${FAKE_OPENCODE_NEXT_PAGE:?}"
    exit
  fi
done
printf '%s' "${FAKE_OPENCODE_SESSIONS:?}"
EOF
chmod +x "$tmp_dir/bin/tmux" "$tmp_dir/bin/opencode"

json='{"data":[
  {"id":"ses_open","title":"Open session","location":{"directory":"/tmp/open"}},
  {"id":"ses_archived","time":{"archived":1},"location":{"directory":"/tmp/archived"}},
  {"id":"ses_child","parentID":"ses_1","location":{"directory":"/tmp/child"}},
  {"id":"ses_no_directory","location":{}},
  {"id":"ses_1","title":"First","location":{"directory":"/tmp/one"}},
  {"id":"ses_2","title":"Second","location":{"directory":"/tmp/two"}},
  {"id":"ses_3","title":"Third","location":{"directory":"/tmp/three"}},
  {"id":"ses_4","title":"Fourth","location":{"directory":"/tmp/four"}},
  {"id":"ses_5","title":"Fifth","location":{"directory":"/tmp/five"}},
  {"id":"ses_6","title":"Sixth","location":{"directory":"/tmp/six"}},
  {"id":"ses_7","title":"Seventh","location":{"directory":"/tmp/seven"}},
  {"id":"ses_8","title":"Eighth","location":{"directory":"/tmp/eight"}},
  {"id":"ses_9","title":"Ninth","location":{"directory":"/tmp/nine"}},
  {"id":"ses_10","title":"Tenth","location":{"directory":"/tmp/ten"}},
  {"id":"ses_11","title":"Eleventh","location":{"directory":"/tmp/eleven"}}
],"cursor":{}}'

run_recent() {
  : >"$tmp_dir/opencode-args.log"
  FAKE_OPENCODE_SESSIONS="${FAKE_OPENCODE_SESSIONS:-$json}" \
    FAKE_TMUX_PANES=$'opencode\tses_open\n' \
    OPENCODE_ARGS_LOG="$tmp_dir/opencode-args.log" \
    OPENCODE_BIN="$tmp_dir/bin/opencode" \
    PATH="$tmp_dir/bin:$PATH" \
    "$@"
}

output="$(run_recent "$RECENT_SCRIPT")"
[[ "$output" != *ses_open* ]]
[[ "$output" != *ses_archived* && "$output" != *ses_child* && "$output" != *ses_no_directory* ]]
[[ "$output" == *$'ses_1\tFirst\t/tmp/one'* ]]
[[ "$output" == *$'ses_10\tTenth\t/tmp/ten'* ]]
[[ "$output" != *ses_11* ]]
[[ "$(printf '%s\n' "$output" | wc -l)" == 10 ]]
grep -qxF -- 'api' "$tmp_dir/opencode-args.log"
grep -qxF -- 'session.list' "$tmp_dir/opencode-args.log"
grep -qxF -- 'parentID=null' "$tmp_dir/opencode-args.log"
grep -qxF -- 'order=desc' "$tmp_dir/opencode-args.log"
grep -qxF -- 'limit=100' "$tmp_dir/opencode-args.log"
[[ "$(grep -cxF call "$tmp_dir/opencode-args.log")" == 1 ]]

no_tmux_output="$(FAKE_TMUX_FAIL=1 run_recent "$RECENT_SCRIPT")"
[[ "$no_tmux_output" == *$'ses_open\tOpen session\t/tmp/open'* ]]
[[ "$no_tmux_output" != *ses_10* ]]
[[ "$(printf '%s\n' "$no_tmux_output" | wc -l)" == 10 ]]

menu_output="$(NO_COLOR=1 run_recent "$MENU_SCRIPT" --list recent)"
[[ "$menu_output" == *$'ses_1\topencode\tsession\t First  /tmp/one\t/tmp/one'* ]]
[[ "$menu_output" == *$'ses_10\topencode\tsession\t Tenth  /tmp/ten\t/tmp/ten'* ]]
[[ "$(printf '%s\n' "$menu_output" | wc -l)" == 10 ]]

first_page="$(jq -c '.data = .data[:6] | .cursor.next = "next-page"' <<< "$json")"
second_page="$(jq -c '.data = .data[6:]' <<< "$json")"
paged_output="$(FAKE_OPENCODE_SESSIONS="$first_page" FAKE_OPENCODE_NEXT_PAGE="$second_page" run_recent "$RECENT_SCRIPT")"
[[ "$paged_output" == "$output" ]]
grep -qxF -- 'cursor=next-page' "$tmp_dir/opencode-args.log"
[[ "$(grep -cxF call "$tmp_dir/opencode-args.log")" == 2 ]]

empty_output="$(FAKE_OPENCODE_SESSIONS='{"data":[],"cursor":{}}' run_recent "$RECENT_SCRIPT")"
[[ -z "$empty_output" ]]

special_output="$(FAKE_OPENCODE_SESSIONS='{"data":[
  {"id":"ses_special","title":"Title\twith\nlines\r!","location":{"directory":"/tmp/project with spaces"}},
  {"id":"ses_untitled","title":null,"location":{"directory":"/tmp/untitled"}}
],"cursor":{}}' run_recent "$RECENT_SCRIPT")"
[[ "$special_output" == $'ses_special\tTitle with lines !\t/tmp/project with spaces\nses_untitled\tses_untitled\t/tmp/untitled' ]]

for script in "$RECENT_SCRIPT" "$MENU_SCRIPT"; do
  if failed_output="$(FAKE_OPENCODE_FAIL=1 run_recent "$script" --list recent 2>"$tmp_dir/error.log")"; then
    printf 'API errors must fail the session list\n' >&2
    exit 1
  fi
  [[ -z "$failed_output" ]]
  grep -qF 'API unavailable' "$tmp_dir/error.log"
done

if failed_output="$(FAKE_OPENCODE_SESSIONS="$first_page" FAKE_OPENCODE_NEXT_FAIL=1 run_recent "$RECENT_SCRIPT" 2>"$tmp_dir/error.log")"; then
  printf 'Pagination errors must fail without partial results\n' >&2
  exit 1
fi
[[ -z "$failed_output" ]]
grep -qF 'Next page unavailable' "$tmp_dir/error.log"

for invalid_json in 'not json' '{"error":"Invalid response"}'; do
  if failed_output="$(FAKE_OPENCODE_SESSIONS="$invalid_json" run_recent "$RECENT_SCRIPT" 2>"$tmp_dir/error.log")"; then
    printf 'Invalid API responses must fail\n' >&2
    exit 1
  fi
  [[ -z "$failed_output" ]]
done

if failed_output="$(FAKE_OPENCODE_SESSIONS="$first_page" FAKE_OPENCODE_NEXT_PAGE='{"data":[],"cursor":{"next":"next-page"}}' run_recent "$RECENT_SCRIPT" 2>"$tmp_dir/error.log")"; then
  printf 'Repeated pagination cursors must fail\n' >&2
  exit 1
fi
[[ -z "$failed_output" ]]
grep -qF 'repeated session cursor' "$tmp_dir/error.log"

[[ "$(FZF_WRAP='' "$VIEW_ACTIONS" recent)" == 'change-prompt(recent  )+toggle-wrap-word+enable-search+unbind(change)' ]]
[[ "$(FZF_WRAP=word "$VIEW_ACTIONS" recent)" == 'change-prompt(recent  )+enable-search+unbind(change)' ]]
[[ "$(FZF_WRAP=word "$VIEW_ACTIONS" projects)" == 'change-prompt(projects  )+toggle-wrap-word+enable-search+unbind(change)' ]]
[[ "$(FZF_WRAP='' "$VIEW_ACTIONS" projects)" == 'change-prompt(projects  )+enable-search+unbind(change)' ]]
[[ "$(FZF_WRAP='' "$VIEW_ACTIONS" find)" == 'change-prompt(find  )+disable-search+rebind(change)' ]]
printf 'OK\n'
