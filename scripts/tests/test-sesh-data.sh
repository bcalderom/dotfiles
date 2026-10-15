#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
MENU_SCRIPT="$REPO_DIR/scripts/tmux/sesh-sessions/sesh-menu"
real_fzf="$(command -v fzf)"
REAL_FD="$(command -v fd)"
export REAL_FD
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/home/a/b/c/deep project"

cat >"$tmp_dir/bin/sesh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  list)
    printf '%s\n' "$@" >"$SESH_ARGS_LOG"
    [[ "${FAKE_SESH_FAIL:-0}" == 0 ]] || { printf 'sesh unavailable\n' >&2; exit 23; }
    printf '%s' "$FAKE_SESH_JSON"
    ;;
  connect) printf '%s\n' "$@" >"$CONNECT_LOG" ;;
  *) exit 1 ;;
esac
EOF
cat >"$tmp_dir/bin/fd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$FD_ARGS_LOG"
[[ "${FAKE_FD_FAIL:-0}" == 0 ]] || { printf 'fd unavailable\n' >&2; exit 24; }
exec "$REAL_FD" "$@"
EOF
cat >"$tmp_dir/bin/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >"$FZF_INPUT_LOG"
printf '%s\0' "$@" >"$FZF_ARGS_LOG"
[[ "${FAKE_FZF_STATUS:-0}" == 0 ]] || exit "$FAKE_FZF_STATUS"
printf '%s' "${FAKE_FZF_SELECTION:-}"
EOF
cat >"$tmp_dir/bin/tds" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$TDS_ARGS_LOG"
EOF
chmod +x "$tmp_dir/bin/"*

export PATH="$tmp_dir/bin:$PATH" HOME="$tmp_dir/home" NO_COLOR=1
export SESH_ARGS_LOG="$tmp_dir/sesh.log" FD_ARGS_LOG="$tmp_dir/fd.log"
export FZF_INPUT_LOG="$tmp_dir/fzf-input.log" CONNECT_LOG="$tmp_dir/connect.log"
export FZF_ARGS_LOG="$tmp_dir/fzf-args.log"
export TDS_ARGS_LOG="$tmp_dir/tds.log"
export FAKE_SESH_JSON
FAKE_SESH_JSON="$(jq -nc '[range(1;9) | {
  Src:"zoxide", Name:("project " + tostring), Path:("/projects/project " + tostring)
}] + [
  {Src:"tmux",Name:"cfg-running",Path:"/projects/running"},
  {Src:"config",Name:"cfg-sesh",Path:"/config/sesh"},
  {Src:"config",Name:" not a tmux session",Path:"/actions"},
  {Src:"unknown",Name:"unsupported",Path:"/unsupported"}
]')"

for mode in projects all; do
  output="$("$MENU_SCRIPT" --list "$mode")"
  [[ "$(awk -F '\t' '$2 == "project" {n++} END {print n+0}' <<< "$output")" == 8 ]]
  [[ "$output" == *$'/projects/project 8\tproject\tdirectory'* ]]
  [[ "$output" != *unsupported* ]]
done
[[ "$output" == *$'cfg-running\ttmux\tsession'* ]]
[[ "$output" == *$' not a tmux session\taction\tdirectory'* ]]
grep -qxF -- '--json' "$SESH_ARGS_LOG"

"$MENU_SCRIPT" --list home --fresh >/dev/null
grep -qxF -- '--no-cache' "$SESH_ARGS_LOG"
"$MENU_SCRIPT" --list home >/dev/null
if grep -qxF -- '--no-cache' "$SESH_ARGS_LOG"; then
  printf 'Normal navigation must keep sesh caching\n' >&2
  exit 1
fi

find_output="$("$MENU_SCRIPT" --list find)"
[[ "$find_output" != *'deep project'* ]]
grep -qxF -- '-d' "$FD_ARGS_LOG"
find_output="$("$MENU_SCRIPT" --list find 'deep PROJECT')"
[[ "$find_output" == *$'deep project/\tfind\tdirectory'* ]]
if grep -qxE -- '-d|--max-depth' "$FD_ARGS_LOG"; then
  printf 'Typed directory searches must not be depth-limited\n' >&2
  exit 1
fi
[[ -z "$("$MENU_SCRIPT" --list find 'no-such-project')" ]]
[[ -z "$("$MENU_SCRIPT" --list find 'deep no-such-project')" ]]

for mode in home find; do
  if FAKE_SESH_FAIL=1 FAKE_FD_FAIL=1 "$MENU_SCRIPT" --list "$mode" >"$tmp_dir/out" 2>"$tmp_dir/error"; then
    printf 'Upstream list errors must propagate\n' >&2
    exit 1
  fi
  [[ ! -s "$tmp_dir/out" && -s "$tmp_dir/error" ]]
done

for invalid_json in 'not json' '{"error":"not an array"}'; do
  if FAKE_SESH_JSON="$invalid_json" "$MENU_SCRIPT" --list home >"$tmp_dir/out" 2>"$tmp_dir/error"; then
    printf 'Invalid session data must fail\n' >&2
    exit 1
  fi
  [[ ! -s "$tmp_dir/out" ]]
done
[[ -z "$(FAKE_SESH_JSON='[]' "$MENU_SCRIPT" --list home)" ]]

rm -f "$FZF_INPUT_LOG"
if FAKE_SESH_FAIL=1 "$MENU_SCRIPT" >"$tmp_dir/out" 2>"$tmp_dir/error"; then
  printf 'Initial list errors must not open an empty picker\n' >&2
  exit 1
fi
[[ ! -e "$FZF_INPUT_LOG" ]]
if FAKE_FZF_STATUS=2 "$MENU_SCRIPT" >"$tmp_dir/out" 2>"$tmp_dir/error"; then
  printf 'fzf errors must propagate\n' >&2
  exit 1
fi
FAKE_FZF_STATUS=130 "$MENU_SCRIPT"
mapfile -d '' -t fzf_arguments <"$FZF_ARGS_LOG"
"$real_fzf" "${fzf_arguments[@]}" --filter=cfg-running <"$FZF_INPUT_LOG" >"$tmp_dir/filtered"
[[ "$(cat "$tmp_dir/filtered")" == $'cfg-running\ttmux\tsession\t/projects/running' ]]

FAKE_FZF_SELECTION=$'/projects/project 8\tproject\tdirectory\t/projects/project 8' "$MENU_SCRIPT"
[[ "$(cat "$CONNECT_LOG")" == $'connect\n/projects/project 8' ]]
FAKE_FZF_SELECTION=$'ses_example\topencode\tsession\t/projects/project 8' "$MENU_SCRIPT"
[[ "$(cat "$TDS_ARGS_LOG")" == $'--directory\n/projects/project 8\n--layout\noc\n--opencode-session\nses_example\n--new-session' ]]

printf 'OK\n'
