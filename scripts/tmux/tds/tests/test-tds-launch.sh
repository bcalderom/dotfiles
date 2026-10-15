#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tmux/tds/layouts.sh
source "$SCRIPT_DIR/../layouts.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/project with spaces" "$tmp_dir/other"
DIR="$tmp_dir/project with spaces"
FAKE_CURRENT_DIRECTORY="$DIR"

escape_shell() { printf '%q' "$1"; }
tmux() {
  case "$1" in
    display-message) printf '%s\n' "$FAKE_CURRENT_DIRECTORY" ;;
    send-keys) printf '%s' "$4" >"$tmp_dir/command" ;;
    *) return 1 ;;
  esac
}

run_in_directory %test 'opencode --session ses_test'
[[ "$(cat "$tmp_dir/command")" == 'opencode --session ses_test' ]]
rm "$tmp_dir/command"
run_in_directory %test
[[ ! -e "$tmp_dir/command" ]]

ln -s "$DIR" "$tmp_dir/link"
DIR="$tmp_dir/link"
run_in_directory %test 'opencode --session ses_test'
[[ "$(cat "$tmp_dir/command")" == 'opencode --session ses_test' ]]

DIR="$tmp_dir/project with spaces"
FAKE_CURRENT_DIRECTORY="$tmp_dir/other"
run_in_directory %test pwd
queued="$(cat "$tmp_dir/command")"
[[ "$queued" == builtin\ cd\ --*\ \&\&\ pwd ]]
actual="$(bash -c 'cd() { return 99; }; '"$queued")"
[[ "$actual" == "$DIR" ]]

DIR="$tmp_dir/missing"
run_in_directory %test "printf 'must-not-run'"
queued="$(cat "$tmp_dir/command")"
if output="$(bash -c "$queued" 2>/dev/null)"; then
  printf 'A failed cd must fail the queued command\n' >&2
  exit 1
fi
[[ -z "$output" ]]

printf 'OK\n'
