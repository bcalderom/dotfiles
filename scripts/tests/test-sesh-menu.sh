#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
SESH_DIR="${REPO_DIR}/.config/sesh"
TMUX_CONFIG="${REPO_DIR}/.config/tmux/tmux.conf"
MENU_SCRIPT="${REPO_DIR}/scripts/tmux/sesh-sessions/sesh-menu"
WIDGET_SCRIPT="${REPO_DIR}/scripts/tmux/sesh-sessions/sesh-sessions"
RENAME_SCRIPT="${SESH_DIR}/scripts/tmux_rename_vim_file"
NVIM_SCRIPT="${SESH_DIR}/scripts/nvim_file_session"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"
assert_eq() {
  if [[ "$1" != "$2" ]]; then
    printf 'Expected %q, got %q\n' "$2" "$1" >&2
    exit 1
  fi
}
assert_contains() {
  if [[ "$1" != *"$2"* ]]; then
    printf 'Expected output to contain %q\n' "$2" >&2
    exit 1
  fi
}
assert_not_contains() {
  if [[ "$1" == *"$2"* ]]; then
    printf 'Expected output not to contain %q\n' "$2" >&2
    exit 1
  fi
}
cat >"$tmp_dir/bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  list-sessions)
    printf '%s' "${FAKE_TMUX_SESSIONS:-}"
    ;;
  rename-session)
    printf '%s' "$2" >"$TMUX_RENAME_LOG"
    ;;
  kill-session)
    printf '%s' "$3" >"$TMUX_KILL_LOG"
    ;;
  *)
    printf 'Unexpected tmux command: %s\n' "$1" >&2
    exit 1
    ;;
esac
EOF
cat >"$tmp_dir/bin/nvim" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'file=%s\n' "${SESH_NVIM_FILE:-}" >"$NVIM_LOG"
printf 'arg=%s\n' "$@" >>"$NVIM_LOG"
EOF
cat >"$tmp_dir/bin/eza" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$EZA_LOG"
printf 'directory listing\n'
EOF
cat >"$tmp_dir/bin/less" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$LESS_ARGS_LOG"
cat >"$LESS_INPUT_LOG"
EOF

chmod +x \
  "$tmp_dir/bin/tmux" \
  "$tmp_dir/bin/nvim" \
  "$tmp_dir/bin/eza" \
  "$tmp_dir/bin/less"

run_rename_test() {
  local sessions="$1"
  local expected="$2"
  : >"$tmp_dir/tmux.log"
  FAKE_TMUX_SESSIONS="$sessions" \
    TMUX="test" \
    TMUX_RENAME_LOG="$tmp_dir/tmux.log" \
    PATH="$tmp_dir/bin:$PATH" \
    "$RENAME_SCRIPT" "/tmp/config.json"
  assert_eq "$(<"$tmp_dir/tmux.log")" "$expected"
}
run_rename_test "" "vim-config.json"
run_rename_test "vim-config.json" "vim-config.json-2"
run_rename_test $'vim-config.json\nvim-config.json-2' "vim-config.json-3"
rm -f "$tmp_dir/tmux.log"
(
  unset TMUX
  TMUX_RENAME_LOG="$tmp_dir/tmux.log" PATH="$tmp_dir/bin:$PATH" \
    "$RENAME_SCRIPT" "/tmp/config.json"
)
if [[ -e "$tmp_dir/tmux.log" ]]; then
  printf 'tmux should not be called outside a tmux session\n' >&2
  exit 1
fi

NVIM_LOG="$tmp_dir/nvim.log" PATH="$tmp_dir/bin:$PATH" \
  "$NVIM_SCRIPT" +"call cursor(6,1)" +startinsert "/tmp/example.lua"
nvim_output="$(<"$tmp_dir/nvim.log")"
assert_contains "$nvim_output" "file="
assert_contains "$nvim_output" "arg=--cmd"
assert_contains "$nvim_output" "autocmd BufReadPost"
assert_contains "$nvim_output" "tmux_rename_vim_file"
assert_contains "$nvim_output" "arg=+call cursor(6,1)"
assert_contains "$nvim_output" "arg=+startinsert"
assert_contains "$nvim_output" "arg=/tmp/example.lua"

NVIM_LOG="$tmp_dir/nvim.log" PATH="$tmp_dir/bin:$PATH" \
  "$NVIM_SCRIPT" --find-files
nvim_output="$(<"$tmp_dir/nvim.log")"
assert_contains "$nvim_output" "file="
assert_not_contains "$nvim_output" "autocmd BufReadPost"
assert_contains "$nvim_output" "telescope.builtin"
assert_contains "$nvim_output" "find_files"
assert_contains "$nvim_output" "select_default:enhance"

NVIM_LOG="$tmp_dir/nvim.log" PATH="$tmp_dir/bin:$PATH" \
  "$NVIM_SCRIPT" --file-browser
nvim_output="$(<"$tmp_dir/nvim.log")"
assert_not_contains "$nvim_output" "autocmd BufReadPost"
assert_contains "$nvim_output" "file_browser"
assert_contains "$nvim_output" "initial_mode = 'insert'"
assert_contains "$nvim_output" "select_default:enhance"

NVIM_LOG="$tmp_dir/nvim.log" HOME="$REPO_DIR" PATH="$tmp_dir/bin:$PATH" \
  "$SESH_DIR/scripts/nvim_find_files"
assert_contains "$(<"$tmp_dir/nvim.log")" "find_files"

NVIM_LOG="$tmp_dir/nvim.log" HOME="$REPO_DIR" PATH="$tmp_dir/bin:$PATH" \
  "$SESH_DIR/scripts/nvim_file_browser"
assert_contains "$(<"$tmp_dir/nvim.log")" "file_browser"

if ! command -v sesh >/dev/null 2>&1; then
  printf 'sesh command not found\n' >&2
  exit 1
fi

sesh_output="$(sesh -C "$SESH_DIR/sesh.toml" list -c -j)"
assert_contains "$sesh_output" '"Name":"vim-file"'
assert_contains "$sesh_output" 'nvim_file_session --find-files'
assert_contains "$sesh_output" '"Name":"cfg-opencode"'
assert_contains "$sesh_output" 'nvim_file_session /home/boris/.config/opencode/config.json'
assert_contains "$sesh_output" 'EDITOR=/home/boris/.config/sesh/scripts/nvim_file_session onn'
assert_contains "$sesh_output" 'nvim_file_session /home/boris/.zshrc'
assert_contains "$sesh_output" 'nvim_file_session /home/boris/.config/tmux/tmux.conf'
assert_contains "$sesh_output" 'nvim_file_session /home/boris/.config/hypr/hyprland.lua'
assert_contains "$sesh_output" 'nvim_file_session /home/boris/.ssh/config'
assert_contains "$sesh_output" 'nvim_file_session /home/boris/.config/sesh/sesh.toml'
assert_contains "$sesh_output" 'eza -alg --color=always --group-directories-first'

tmux_config="$(<"$TMUX_CONFIG")"
assert_contains "$tmux_config" 'display-popup -E -w 75% -h 60%'
assert_contains "$tmux_config" 'scripts/tmux/sesh-sessions/sesh-menu'

menu_source="$(<"$MENU_SCRIPT")"
assert_contains "$menu_source" 'ctrl-e:transform('
assert_contains "$menu_source" '--open-action {1} {2} {3}'
assert_contains "$menu_source" 'ctrl-r:transform($SCRIPT_DIR/fzf-view-actions recent)'

actions_output="$(NO_COLOR=1 "$MENU_SCRIPT" --list actions)"
configs_output="$(NO_COLOR=1 "$MENU_SCRIPT" --list configs)"
projects_output="$(NO_COLOR=1 "$MENU_SCRIPT" --list projects)"
all_output="$(NO_COLOR=1 "$MENU_SCRIPT" --list all)"
assert_contains "$actions_output" ' terminal-local'
assert_contains "$actions_output" ' vim-file'
assert_contains "$actions_output" ' tds-oc'
assert_contains "$actions_output" '󰣀 ssh-connect'
assert_contains "$actions_output" '󰎚 notes-new'
assert_contains "$actions_output" '󰂺 notes-vault'
assert_contains "$actions_output" ' files-downloads'
assert_not_contains "$actions_output" 'cfg-'
assert_contains "$configs_output" ' cfg-sesh'
assert_not_contains "$configs_output" 'vim-file'
assert_contains "$configs_output" $'cfg-sesh\tconfig\tfile'
assert_contains "$configs_output" $'cfg-dotfiles\tconfig\tdirectory'
assert_eq "$(printf '%s\n' "$projects_output" | awk -F '\t' '$2 == "project" { count++ } END { print count + 0 }')" '5'
assert_eq "$(printf '%s\n' "$all_output" | awk -F '\t' '$2 == "project" { count++ } END { print count + 0 }')" '5'

selection="$(
  printf '%s\n' "$actions_output" | fzf \
    --ansi --delimiter=$'\t' --with-nth=4 --accept-nth=1 \
    --filter='vim-file'
)"
assert_eq "$selection" 'vim-file'

rm -f "$tmp_dir/tmux-kill.log"
TMUX_KILL_LOG="$tmp_dir/tmux-kill.log" PATH="$tmp_dir/bin:$PATH" \
  "$MENU_SCRIPT" --kill 'cfg-sesh' 'config'
if [[ -e "$tmp_dir/tmux-kill.log" ]]; then
  printf 'Non-tmux rows must not kill sessions\n' >&2
  exit 1
fi

TMUX_KILL_LOG="$tmp_dir/tmux-kill.log" PATH="$tmp_dir/bin:$PATH" \
  "$MENU_SCRIPT" --kill 'vim-example.lua' 'tmux'
assert_eq "$(<"$tmp_dir/tmux-kill.log")" 'vim-example.lua'

tmux_header="$("$MENU_SCRIPT" --header 'tmux' 'session')"
file_header="$("$MENU_SCRIPT" --header 'config' 'file')"
directory_header="$("$MENU_SCRIPT" --header 'project' 'directory')"
opencode_header="$("$MENU_SCRIPT" --header 'opencode' 'session')"
assert_contains "$tmux_header" '^d kill'
assert_not_contains "$tmux_header" '^e explorer'
assert_contains "$file_header" '^/ search'
assert_not_contains "$file_header" '^e explorer'
assert_contains "$directory_header" '^e explorer'
assert_contains "$directory_header" 'M-k/j preview'
assert_contains "$opencode_header" 'enter resume'
assert_contains "$opencode_header" '^r recent'

mkdir -p "$tmp_dir/preview-dir"
EZA_LOG="$tmp_dir/eza.log" PATH="$tmp_dir/bin:$PATH" \
  "$MENU_SCRIPT" --preview "$tmp_dir/preview-dir" 'find' 'directory' \
  >"$tmp_dir/preview.log"
eza_args="$(<"$tmp_dir/eza.log")"
assert_contains "$eza_args" '-alg'
assert_contains "$eza_args" '--color=always'
assert_contains "$eza_args" '--group-directories-first'
assert_contains "$eza_args" "$tmp_dir/preview-dir"

EZA_LOG="$tmp_dir/eza.log" \
  LESS_ARGS_LOG="$tmp_dir/less-args.log" \
  LESS_INPUT_LOG="$tmp_dir/less-input.log" \
  PATH="$tmp_dir/bin:$PATH" \
  "$MENU_SCRIPT" --view "$tmp_dir/preview-dir" 'find' 'directory'
assert_contains "$(<"$tmp_dir/less-args.log")" '-R'
assert_contains "$(<"$tmp_dir/less-input.log")" 'directory listing'

config_preview="$("$MENU_SCRIPT" --preview 'cfg-sesh' 'config' 'file')"
assert_contains "$config_preview" '[[session]]'

opencode_preview="$("$MENU_SCRIPT" --preview 'cfg-opencode' 'config' 'file')"
assert_not_contains "$opencode_preview" 'CONTEXT7_API_KEY'

widget_source="$(<"$WIDGET_SCRIPT")"
assert_contains "$widget_source" 'scripts/tmux/sesh-sessions/sesh-menu'
assert_not_contains "$widget_source" 'sesh list'

cat >"$tmp_dir/bin/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"$FZF_ARGS_LOG"
exit 1
EOF
chmod +x "$tmp_dir/bin/fzf"

rm -f "$tmp_dir/fzf-outside.log"
(
  unset TMUX
  FZF_ARGS_LOG="$tmp_dir/fzf-outside.log" PATH="$tmp_dir/bin:$PATH" \
    "$MENU_SCRIPT"
)
outside_fzf_args="$(<"$tmp_dir/fzf-outside.log")"
assert_contains "$outside_fzf_args" '--layout=default'
assert_contains "$outside_fzf_args" '--margin=20%,12.5%'
assert_contains "$outside_fzf_args" '--border'

rm -f "$tmp_dir/fzf-tmux.log"
TMUX='test' \
  FAKE_TMUX_SESSIONS='' \
  FZF_ARGS_LOG="$tmp_dir/fzf-tmux.log" \
  PATH="$tmp_dir/bin:$PATH" \
  "$MENU_SCRIPT"
tmux_fzf_args="$(<"$tmp_dir/fzf-tmux.log")"
assert_contains "$tmux_fzf_args" '--layout=default'
assert_not_contains "$tmux_fzf_args" '--margin=20%,12.5%'

printf 'OK\n'
