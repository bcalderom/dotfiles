#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TRANSFER="${SCRIPT_DIR}/../ssf-transfer"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

MOCK_BIN="${TMPDIR}/bin"
WORK="${TMPDIR}/work"
mkdir -p "$MOCK_BIN" "$WORK/sub dir" "$WORK/downloads"
printf 'one\n' > "$WORK/file one.txt"
printf 'two\n' > "$WORK/file-two.txt"
printf 'nested\n' > "$WORK/sub dir/nested file.txt"

cat > "$MOCK_BIN/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
prompt=''
for arg in "$@"; do
  case "$arg" in --prompt=*) prompt="${arg#--prompt=}" ;; esac
done
input="$(mktemp)"
trap 'rm -f "$input"' EXIT
cat > "$input"

case "$prompt" in
  'direction> ')
    printf '%s\n' "${SSF_TEST_DIRECTION}"$'\t'"selected direction"
    ;;
  'source> ')
    count=0
    [[ ! -f "${SSF_TEST_SOURCE_COUNT}" ]] || read -r count < "${SSF_TEST_SOURCE_COUNT}"
    count=$((count + 1))
    printf '%s\n' "$count" > "${SSF_TEST_SOURCE_COUNT}"
    if [[ -n "${SSF_TEST_NAV_DIR:-}" && $count -eq 1 ]]; then
      printf 'ctrl-d\0[D] %s\0' "${SSF_TEST_NAV_DIR}"
    elif [[ -n "${SSF_TEST_NAV_FILE:-}" ]]; then
      tr '\0' '\n' < "$input" > "${SSF_TEST_LAST_SOURCE_INPUT}"
      printf 'ctrl-a\0[F] %s\0' "${SSF_TEST_NAV_FILE}"
    elif [[ "${SSF_TEST_CANCEL_SOURCE:-0}" == 1 ]]; then
      exit 130
    else
      printf 'ctrl-a\0'
      cat "${SSF_TEST_SOURCE_RECORDS}"
    fi
    ;;
  'destination> ')
    if [[ -n "${SSF_TEST_DESTINATION_INPUT:-}" ]]; then
      tr '\0' '\n' < "$input" > "${SSF_TEST_DESTINATION_INPUT}"
    fi
    printf 'ctrl-a\0[C] %s\0' "${SSF_TEST_DESTINATION}"
    ;;
  'directory mode> ')
    printf '%s\n' "${SSF_TEST_DIRECTORY_MODE}"$'\t'"selected directory mode"
    ;;
  'next> ')
    ncount=0
    if [[ -n "${SSF_TEST_NEXT_COUNT:-}" ]]; then
      [[ ! -f "$SSF_TEST_NEXT_COUNT" ]] || read -r ncount < "$SSF_TEST_NEXT_COUNT"
      ncount=$((ncount + 1))
      printf '%s\n' "$ncount" > "$SSF_TEST_NEXT_COUNT"
    fi
    if [[ "$ncount" -eq 1 && -n "${SSF_TEST_NEXT_FIRST:-}" ]]; then
      printf '%s\t%s\n' "${SSF_TEST_NEXT_FIRST}" 'selected next action'
    else
      printf '%s\t%s\n' "${SSF_TEST_NEXT:-quit}" 'selected next action'
    fi
    ;;
  *)
    echo "Unexpected fzf prompt: $prompt" >&2
    exit 2
    ;;
esac
EOF

cat > "$MOCK_BIN/scp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${SSF_TEST_COMMAND_COUNT:-}" ]]; then
  count=0
  [[ ! -f "${SSF_TEST_COMMAND_COUNT}" ]] || read -r count < "${SSF_TEST_COMMAND_COUNT}"
  printf '%s\n' "$((count + 1))" > "${SSF_TEST_COMMAND_COUNT}"
fi
printf '%s\0' "$@" > "${SSF_TEST_COMMAND_LOG}"
EOF

cat > "$MOCK_BIN/rsync" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" > "${SSF_TEST_COMMAND_LOG}"
EOF
cat > "$MOCK_BIN/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ -z "${SSF_TEST_SSH_LOG:-}" ]] || printf '%s\n' "$*" > "${SSF_TEST_SSH_LOG}"
EOF

cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ -z "${SSF_TEST_TMUX_LOG:-}" ]] || printf '%s\n' "$*" >> "${SSF_TEST_TMUX_LOG}"
case "${1:-}" in
  display-message) printf '%s\n' "${SSF_TEST_TMUX_SESSION:-}" ;;
  has-session) exit 1 ;;
esac
exit 0
EOF
chmod +x "$MOCK_BIN/fzf" "$MOCK_BIN/scp" "$MOCK_BIN/rsync" "$MOCK_BIN/ssh" "$MOCK_BIN/tmux"

assert_args() {
  local log="$1"
  shift
  local -a actual=()
  mapfile -d '' -t actual < "$log"
  if [[ ${#actual[@]} -ne $# ]]; then
    echo "Expected $# arguments, got ${#actual[@]}" >&2
    printf '  <%s>\n' "${actual[@]}" >&2
    exit 1
  fi
  local index=0 expected
  for expected in "$@"; do
    if [[ "${actual[$index]}" != "$expected" ]]; then
      echo "Argument $index: expected <$expected>, got <${actual[$index]}>" >&2
      exit 1
    fi
    index=$((index + 1))
  done
}

SOURCE_RECORDS="${TMPDIR}/source-records"
SOURCE_COUNT="${TMPDIR}/source-count"
COMMAND_LOG="${TMPDIR}/command-log"
COMMAND_COUNT="${TMPDIR}/command-count"
LAST_SOURCE_INPUT="${TMPDIR}/last-source-input"
DESTINATION_INPUT="${TMPDIR}/destination-input"
NEXT_COUNT="${TMPDIR}/next-count"
SSH_LOG="${TMPDIR}/ssh-log"
TMUX_LOG="${TMPDIR}/tmux-log"
MAIN_LOG="${TMPDIR}/main-log"

printf '[F] %s\0[F] %s\0' "$WORK/file one.txt" "$WORK/file-two.txt" > "$SOURCE_RECORDS"
printf 'docs and files\n' | (
  cd "$WORK"
  PATH="$MOCK_BIN:$PATH" \
  SSF_TEST_DIRECTION=upload \
  SSF_TEST_SOURCE_RECORDS="$SOURCE_RECORDS" \
  SSF_TEST_SOURCE_COUNT="$SOURCE_COUNT" \
  SSF_TEST_COMMAND_LOG="$COMMAND_LOG" \
  bash "$TRANSFER" scp demo boris example.test
) >/dev/null
assert_args "$COMMAND_LOG" -r -- "$WORK/file one.txt" "$WORK/file-two.txt" 'demo:~/docs and files'

rm -f "$SOURCE_COUNT"
printf 'nested-target\n' | (
  cd "$WORK"
  PATH="$MOCK_BIN:$PATH" \
  SSF_TEST_DIRECTION=upload \
  SSF_TEST_NAV_DIR="$WORK/sub dir" \
  SSF_TEST_NAV_FILE="$WORK/sub dir/nested file.txt" \
  SSF_TEST_SOURCE_COUNT="$SOURCE_COUNT" \
  SSF_TEST_LAST_SOURCE_INPUT="$LAST_SOURCE_INPUT" \
  SSF_TEST_COMMAND_LOG="$COMMAND_LOG" \
  bash "$TRANSFER" scp demo boris example.test
) >/dev/null
assert_args "$COMMAND_LOG" -r -- "$WORK/sub dir/nested file.txt" 'demo:~/nested-target'
if ! grep -F -- "[F] $WORK/sub dir/nested file.txt" "$LAST_SOURCE_INPUT" >/dev/null; then
  echo 'Expected source browser to list the entered directory' >&2
  exit 1
fi

printf 'logs/system.log\n' | (
  cd "$WORK"
  PATH="$MOCK_BIN:$PATH" \
  SSF_TEST_DIRECTION=download \
  SSF_TEST_DESTINATION="$WORK/downloads" \
  SSF_TEST_DESTINATION_INPUT="$DESTINATION_INPUT" \
  SSF_TEST_COMMAND_LOG="$COMMAND_LOG" \
  bash "$TRANSFER" scp demo boris example.test
) >/dev/null
assert_args "$COMMAND_LOG" -r -- 'demo:~/logs/system.log' "$WORK/downloads"
if grep -F -- '[F] ' "$DESTINATION_INPUT" >/dev/null; then
  echo 'Download destination browser must only list directories' >&2
  exit 1
fi

printf '[D] %s\0' "$WORK/sub dir" > "$SOURCE_RECORDS"
printf 'backup\n' | (
  cd "$WORK"
  PATH="$MOCK_BIN:$PATH" \
  SSF_TEST_DIRECTION=upload \
  SSF_TEST_SOURCE_RECORDS="$SOURCE_RECORDS" \
  SSF_TEST_SOURCE_COUNT="$SOURCE_COUNT" \
  SSF_TEST_DIRECTORY_MODE=contents \
  SSF_TEST_COMMAND_LOG="$COMMAND_LOG" \
  bash "$TRANSFER" rsync demo boris example.test
) >/dev/null
assert_args "$COMMAND_LOG" -avz --progress --protect-args -- "$WORK/sub dir/" 'demo:~/backup'

printf 'backup-dir\n' | (
  cd "$WORK"
  PATH="$MOCK_BIN:$PATH" \
  SSF_TEST_DIRECTION=upload \
  SSF_TEST_SOURCE_RECORDS="$SOURCE_RECORDS" \
  SSF_TEST_SOURCE_COUNT="$SOURCE_COUNT" \
  SSF_TEST_DIRECTORY_MODE=directory \
  SSF_TEST_COMMAND_LOG="$COMMAND_LOG" \
  bash "$TRANSFER" rsync demo boris example.test
) >/dev/null
assert_args "$COMMAND_LOG" -avz --progress --protect-args -- "$WORK/sub dir" 'demo:~/backup-dir'

rm -f "$COMMAND_LOG" "$SOURCE_COUNT"
cancel_output="$(
  cd "$WORK"
  PATH="$MOCK_BIN:$PATH" \
  SSF_TEST_DIRECTION=upload \
  SSF_TEST_CANCEL_SOURCE=1 \
  SSF_TEST_SOURCE_COUNT="$SOURCE_COUNT" \
  SSF_TEST_COMMAND_LOG="$COMMAND_LOG" \
  bash "$TRANSFER" scp demo boris example.test || true
)"
[[ "$cancel_output" == *'Cancelled.'* ]] || { echo 'Expected cancellation message' >&2; exit 1; }
[[ ! -e "$COMMAND_LOG" ]] || { echo 'Cancelled transfer must not call scp' >&2; exit 1; }

printf '[F] %s\0[F] %s\0' "$WORK/file one.txt" "$WORK/file-two.txt" > "$SOURCE_RECORDS"

rm -f "$SOURCE_COUNT" "$COMMAND_COUNT" "$NEXT_COUNT"
printf 'first-path\nsecond-path\n' | (
  cd "$WORK"
  PATH="$MOCK_BIN:$PATH" \
  SSF_TEST_DIRECTION=upload \
  SSF_TEST_SOURCE_RECORDS="$SOURCE_RECORDS" \
  SSF_TEST_SOURCE_COUNT="$SOURCE_COUNT" \
  SSF_TEST_COMMAND_LOG="$COMMAND_LOG" \
  SSF_TEST_COMMAND_COUNT="$COMMAND_COUNT" \
  SSF_TEST_NEXT_COUNT="$NEXT_COUNT" \
  SSF_TEST_NEXT_FIRST=again \
  SSF_TEST_NEXT=quit \
  bash "$TRANSFER" scp demo boris example.test
) >/dev/null
[[ "$(cat "$COMMAND_COUNT")" == 2 ]] || { echo 'Expected again to run two transfers' >&2; exit 1; }
assert_args "$COMMAND_LOG" -r -- "$WORK/file one.txt" "$WORK/file-two.txt" 'demo:~/second-path'

rm -f "$SOURCE_COUNT" "$SSH_LOG" "$TMUX_LOG"
printf 'ssh-target\n' | (
  cd "$WORK"
  PATH="$MOCK_BIN:$PATH" \
  TMUX='/tmp/ssf-test-tmux' \
  SSF_TEST_DIRECTION=upload \
  SSF_TEST_SOURCE_RECORDS="$SOURCE_RECORDS" \
  SSF_TEST_SOURCE_COUNT="$SOURCE_COUNT" \
  SSF_TEST_COMMAND_LOG="$COMMAND_LOG" \
  SSF_TEST_NEXT=ssh \
  SSF_TEST_SSH_LOG="$SSH_LOG" \
  SSF_TEST_TMUX_LOG="$TMUX_LOG" \
  SSF_TEST_TMUX_SESSION='scp-demo' \
  bash "$TRANSFER" scp demo boris example.test
) >/dev/null
[[ "$(cat "$SSH_LOG")" == 'demo' ]] || { echo 'Expected post-action ssh to connect to demo' >&2; exit 1; }
grep -F 'rename-window -- ssh-demo' "$TMUX_LOG" >/dev/null || { echo 'Expected window rename to ssh-demo' >&2; exit 1; }
grep -F 'rename-session -t scp-demo ssh-demo' "$TMUX_LOG" >/dev/null || { echo 'Expected session rename to ssh-demo' >&2; exit 1; }

MAIN_STUB="${TMPDIR}/ssf-main-stub"
cat > "$MAIN_STUB" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'main menu invoked\n' > "${SSF_TEST_MAIN_LOG}"
EOF
chmod +x "$MAIN_STUB"

rm -f "$SOURCE_COUNT" "$MAIN_LOG"
printf 'menu-target\n' | (
  cd "$WORK"
  PATH="$MOCK_BIN:$PATH" \
  SSF_MAIN_PATH="$MAIN_STUB" \
  SSF_TEST_MAIN_LOG="$MAIN_LOG" \
  SSF_TEST_DIRECTION=upload \
  SSF_TEST_SOURCE_RECORDS="$SOURCE_RECORDS" \
  SSF_TEST_SOURCE_COUNT="$SOURCE_COUNT" \
  SSF_TEST_COMMAND_LOG="$COMMAND_LOG" \
  SSF_TEST_NEXT=menu \
  bash "$TRANSFER" scp demo boris example.test
) >/dev/null
[[ "$(cat "$MAIN_LOG")" == 'main menu invoked' ]] || { echo 'Expected post-action menu to invoke ssf main script' >&2; exit 1; }

echo 'OK'
