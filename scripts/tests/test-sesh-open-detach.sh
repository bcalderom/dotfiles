#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
MENU_SCRIPT="${REPO_DIR}/scripts/tmux/sesh-sessions/sesh-menu"

tmp_dir="$(mktemp -d)"
socket="sesh-open-test-$$"
trap 'tmux -L "$socket" kill-server 2>/dev/null || true; rm -rf "$tmp_dir"' EXIT

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

mkdir -p "$tmp_dir/home/example dir" "$tmp_dir/unit-bin" "$tmp_dir/detach-bin"

cat >"$tmp_dir/unit-bin/xdg-open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s' "$1" >"$OPEN_DIRECTORY_LOG"
EOF

cat >"$tmp_dir/unit-bin/setsid" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$SETSID_LOG"
[[ "$1" == "--fork" ]] && shift
[[ "$1" == "--" ]] && shift
"$@"
EOF

chmod +x "$tmp_dir/unit-bin/xdg-open" "$tmp_dir/unit-bin/setsid"

action="$(
  HOME="$tmp_dir/home" \
    OPEN_DIRECTORY_LOG="$tmp_dir/open.log" \
    SETSID_LOG="$tmp_dir/setsid.log" \
    PATH="$tmp_dir/unit-bin:$PATH" \
    "$MENU_SCRIPT" --open-action '~/example dir' project directory
)"
assert_eq "$action" abort
assert_eq "$(<"$tmp_dir/open.log")" "$tmp_dir/home/example dir"
setsid_args="$(<"$tmp_dir/setsid.log")"
assert_contains "$setsid_args" '--fork'
assert_contains "$setsid_args" 'xdg-open'
assert_contains "$setsid_args" "$tmp_dir/home/example dir"

rm -f "$tmp_dir/open.log" "$tmp_dir/setsid.log"
action="$(
  HOME="$tmp_dir/home" \
    OPEN_DIRECTORY_LOG="$tmp_dir/open.log" \
    SETSID_LOG="$tmp_dir/setsid.log" \
    PATH="$tmp_dir/unit-bin:$PATH" \
    "$MENU_SCRIPT" --open-action cfg-sesh config file
)"
assert_eq "$action" ''
[[ ! -e "$tmp_dir/open.log" && ! -e "$tmp_dir/setsid.log" ]]

cat >"$tmp_dir/detach-bin/xdg-open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep "${OPEN_DELAY:-0.4}"
printf '%s' "$1" >"$OPEN_DIRECTORY_LOG"
EOF
chmod +x "$tmp_dir/detach-bin/xdg-open"

tmux -L "$socket" -f /dev/null new-session -d -s open-test \
  env \
  HOME="$tmp_dir/home" \
  OPEN_DELAY=0.4 \
  OPEN_DIRECTORY_LOG="$tmp_dir/detached-open.log" \
  PATH="$tmp_dir/detach-bin:/usr/bin:/bin" \
  "$MENU_SCRIPT" --open '~/example dir' project directory

sleep 0.05
tmux -L "$socket" kill-server 2>/dev/null || true

for _ in {1..30}; do
  [[ -e "$tmp_dir/detached-open.log" ]] && break
  sleep 0.05
done

if [[ ! -e "$tmp_dir/detached-open.log" ]]; then
  printf 'Detached opener did not survive tmux shutdown\n' >&2
  exit 1
fi
assert_eq "$(<"$tmp_dir/detached-open.log")" "$tmp_dir/home/example dir"

printf 'OK\n'
