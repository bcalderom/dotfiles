#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
MENU_SCRIPT="${REPO_DIR}/.config/hypr/scripts/quick-menu.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/quick-menu.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"

cat > "$tmp_dir/bin/fake-command" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command="${0##*/}"
printf '%s' "$command" >> "$TEST_DIR/commands"
printf ' %s' "$@" >> "$TEST_DIR/commands"
printf '\n' >> "$TEST_DIR/commands"
case "$command" in
  systemctl)
    case "$1" in
      show)
        unit="${@: -1}"
        if [[ "${FAKE_STATE_FAIL:-}" == "$unit" ]] ||
          { [[ -f "$TEST_DIR/stopped" ]] && [[ "${FAKE_VERIFY_STATE_FAIL:-}" == "$unit" ]]; }; then
          printf 'Cannot read unit state\n' >&2
          exit 1
        fi
        if [[ -f "$TEST_DIR/stopped" && "${FAKE_KEEP_ACTIVE:-}" != "$unit" ]]; then
          printf 'inactive\n'
          exit 0
        fi
        case "$unit" in
          docker.service) printf '%s\n' "${FAKE_DOCKER_STATE:-active}" ;;
          docker.socket) printf '%s\n' "${FAKE_SOCKET_STATE:-active}" ;;
          containerd.service) printf '%s\n' "${FAKE_CONTAINERD_STATE:-active}" ;;
          *) exit 2 ;;
        esac
        ;;
      stop)
        [[ "$*" == 'stop docker.socket docker.service containerd.service' ]] || exit 2
        if [[ "${FAKE_SERVICE_STOP_FAIL:-0}" == 1 ]]; then
          printf 'Service stop failed\n' >&2
          exit 1
        fi
        touch "$TEST_DIR/stopped"
        ;;
      start) ;;
      *) exit 2 ;;
    esac
    ;;
  docker)
    [[ "$1" == --host && "$2" == unix:///run/docker.sock ]] || exit 2
    [[ -z "${DOCKER_HOST+x}${DOCKER_CONTEXT+x}${DOCKER_TLS_VERIFY+x}${DOCKER_CERT_PATH+x}" ]] || exit 2
    shift 2
    case "$1" in
      ps)
        read -r query < "$TEST_DIR/query-count"
        query=$((query + 1))
        printf '%s\n' "$query" > "$TEST_DIR/query-count"
        if [[ "${FAKE_QUERY_FAIL_AT:-0}" == "$query" ]]; then
          printf 'permission denied connecting to Docker\n' >&2
          exit 1
        fi
        case "$query" in
          1) printf '%s' "${FAKE_CONTAINERS:-}" ;;
          2) printf '%s' "${FAKE_RECHECK_CONTAINERS-${FAKE_CONTAINERS:-}}" ;;
          *) printf '%s' "${FAKE_FINAL_CONTAINERS:-}" ;;
        esac
        if [[ "${FAKE_DAEMON_DISAPPEARS:-0}" == 1 ]]; then
          touch "$TEST_DIR/stopped"
        fi
        ;;
      stop)
        [[ "$2" == --timeout && "$3" == 30 ]] || exit 2
        if [[ "${FAKE_CONTAINER_STOP_FAIL:-0}" == 1 ]]; then
          printf 'Container stop failed\n' >&2
          exit 1
        fi
        ;;
      *) exit 2 ;;
    esac
    ;;
  pkexec)
    if [[ "${FAKE_AUTH_FAIL:-0}" == 1 ]]; then
      printf 'Authorization cancelled\n' >&2
      exit 126
    fi
    "$@"
    ;;
  rofi)
    input="$(cat)"
    if [[ "$*" == *'Acción rápida'* ]]; then
      printf '%s\n' "$input" > "$TEST_DIR/menu-input"
      printf '%s\n' "${FAKE_MENU_CHOICE:-Docker: detener servicios}"
    else
      printf '%s\n' "$input" > "$TEST_DIR/confirmation-input"
      printf '%s\n' "${FAKE_ROFI_CHOICE:-Detener}"
      exit "${FAKE_ROFI_STATUS:-0}"
    fi
    ;;
  notify-send) ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$tmp_dir/bin/fake-command"
for command in systemctl docker pkexec rofi notify-send; do
  ln -s fake-command "$tmp_dir/bin/$command"
done

export SYSTEMCTL_BIN="$tmp_dir/bin/systemctl"
export DOCKER_BIN="$tmp_dir/bin/docker"
export PKEXEC_BIN="$tmp_dir/bin/pkexec"
export ROFI_BIN="$tmp_dir/bin/rofi"
export NOTIFY_SEND_BIN="$tmp_dir/bin/notify-send"
# These must never redirect the action to a remote daemon or enable TLS.
export DOCKER_HOST=tcp://remote.invalid:2376 DOCKER_CONTEXT=remote
export DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH=/invalid

tests=0
run_case() {
  local expected_status="$1" actual_status=0
  shift
  tests=$((tests + 1))
  export TEST_DIR="$tmp_dir/case-$tests"
  mkdir -p "$TEST_DIR"
  : > "$TEST_DIR/commands"
  printf '0\n' > "$TEST_DIR/query-count"
  env "$@" bash "$MENU_SCRIPT" docker-stop || actual_status=$?
  if [[ "$actual_status" != "$expected_status" ]]; then
    printf 'Case %s: expected status %s, got %s\n' "$tests" "$expected_status" "$actual_status" >&2
    exit 1
  fi
  log="$(<"$TEST_DIR/commands")"
}
assert_contains() {
  if [[ "$log" != *"$1"* ]]; then
    printf 'Case %s: expected log to contain %q\n%s\n' "$tests" "$1" "$log" >&2
    exit 1
  fi
}
assert_not_contains() {
  if [[ "$log" == *"$1"* ]]; then
    printf 'Case %s: unexpected %q\n%s\n' "$tests" "$1" "$log" >&2
    exit 1
  fi
}
assert_no_stop() {
  assert_not_contains 'docker --host unix:///run/docker.sock stop'
  assert_not_contains 'pkexec'
}
assert_service_stop() {
  assert_contains "pkexec $SYSTEMCTL_BIN stop docker.socket docker.service containerd.service"
}
containers=$'aaa111 api\nbbb222 database'

# Empty daemon: no confirmation; all services stopped and verified.
run_case 0
assert_not_contains 'rofi'
assert_not_contains 'docker --host unix:///run/docker.sock stop'
assert_service_stop
assert_contains 'Docker, su socket y containerd detenidos'
[[ "$(<"$TEST_DIR/query-count")" == 3 ]]

# Active containers: explicit confirmation and graceful stop before services.
run_case 0 FAKE_CONTAINERS="$containers"
assert_contains 'rofi -dmenu -i -no-custom -selected-row 0'
assert_contains 'Hay 2 contenedores activos:'
assert_contains '• api'
assert_contains '• database'
[[ "$(<"$TEST_DIR/confirmation-input")" == $'Cancelar\nDetener' ]]
assert_contains 'docker --host unix:///run/docker.sock stop --timeout 30 aaa111 bbb222'
assert_service_stop
[[ "$log" == *'stop --timeout 30 aaa111 bbb222'*"pkexec $SYSTEMCTL_BIN stop"* ]]

# Cancel, Escape and arbitrary text never authorize a stop.
run_case 0 FAKE_CONTAINERS="$containers" FAKE_ROFI_CHOICE=Cancelar
assert_no_stop
assert_not_contains 'detenidos'
run_case 0 FAKE_CONTAINERS="$containers" FAKE_ROFI_STATUS=1
assert_no_stop
run_case 0 FAKE_CONTAINERS="$containers" FAKE_ROFI_CHOICE=otro
assert_no_stop

# Long container lists are bounded in the confirmation message.
run_case 0 FAKE_CONTAINERS=$'a one\nb two\nc three\nd four\ne five\nf six\ng seven' FAKE_ROFI_CHOICE=Cancelar
assert_contains 'Hay 7 contenedores activos:'
assert_contains '• five'
assert_contains '… y 2 más'
assert_not_contains '• six'
assert_no_stop

# No daemon query when already stopped or when only its socket is active.
run_case 0 FAKE_DOCKER_STATE=inactive FAKE_SOCKET_STATE=inactive FAKE_CONTAINERD_STATE=inactive
assert_contains 'Los servicios de Docker ya están detenidos'
assert_not_contains 'docker --host'
assert_no_stop
run_case 0 FAKE_DOCKER_STATE=inactive FAKE_CONTAINERD_STATE=inactive
assert_not_contains 'docker --host'
assert_service_stop

# A running containerd without the daemon may hold live-restore containers.
run_case 1 FAKE_DOCKER_STATE=inactive
assert_contains 'No se puede verificar si quedan contenedores'
assert_not_contains 'docker --host'
assert_no_stop

# Failed queries are not interpreted as an empty container list.
run_case 1 FAKE_QUERY_FAIL_AT=1
assert_contains 'No se pudieron consultar los contenedores locales'
assert_no_stop
run_case 1 FAKE_QUERY_FAIL_AT=2 FAKE_CONTAINERS="$containers"
assert_no_stop
run_case 1 FAKE_STATE_FAIL=docker.socket
assert_contains 'No se pudo consultar docker.socket'
assert_no_stop
run_case 1 FAKE_DOCKER_STATE=activating
assert_contains 'estado inesperado: activating'
assert_not_contains 'docker --host'
assert_no_stop
run_case 1 FAKE_CONTAINERS="$containers" FAKE_DAEMON_DISAPPEARS=1
assert_contains 'Docker no está activo'
[[ "$(<"$TEST_DIR/query-count")" == 1 ]]
assert_no_stop

# Newly started containers need a new confirmation, including after an empty list.
run_case 1 FAKE_RECHECK_CONTAINERS='ccc333 worker'
assert_contains 'Aparecieron nuevos contenedores activos (worker)'
assert_no_stop
run_case 1 FAKE_CONTAINERS="$containers" FAKE_RECHECK_CONTAINERS=$'aaa111 api\nccc333 worker'
assert_contains 'Aparecieron nuevos contenedores activos (worker)'
assert_no_stop

# Already exited containers are excluded from the graceful stop command.
run_case 0 FAKE_CONTAINERS="$containers" FAKE_RECHECK_CONTAINERS='bbb222 database'
assert_contains 'stop --timeout 30 bbb222'
assert_not_contains 'stop --timeout 30 aaa111'
assert_service_stop

# Container-stop errors and remaining containers prevent stopping services.
run_case 1 FAKE_CONTAINERS="$containers" FAKE_CONTAINER_STOP_FAIL=1
assert_contains 'No se pudieron detener todos los contenedores'
assert_not_contains 'pkexec'
run_case 1 FAKE_CONTAINERS="$containers" FAKE_FINAL_CONTAINERS='ccc333 worker'
assert_contains 'Todavía hay contenedores activos'
assert_not_contains 'pkexec'
run_case 1 FAKE_CONTAINERS="$containers" FAKE_QUERY_FAIL_AT=3
assert_not_contains 'pkexec'

# Authorization, service-stop and final-state failures never report success.
run_case 1 FAKE_AUTH_FAIL=1
assert_contains 'Authorization cancelled'
assert_not_contains $'\nsystemctl stop '
assert_not_contains 'Docker, su socket y containerd detenidos'
run_case 1 FAKE_SERVICE_STOP_FAIL=1
assert_contains 'Service stop failed'
assert_not_contains 'Docker, su socket y containerd detenidos'
run_case 1 FAKE_KEEP_ACTIVE=docker.socket
assert_contains 'docker.socket no quedó detenido'
assert_not_contains 'Docker, su socket y containerd detenidos'
run_case 1 FAKE_VERIFY_STATE_FAIL=containerd.service
assert_contains 'No se pudo consultar containerd.service'
assert_not_contains 'Docker, su socket y containerd detenidos'

# Both the visible menu entry and its label dispatch to the same action.
run_case 0
bash "$MENU_SCRIPT"
[[ "$(<"$TEST_DIR/menu-input")" == *'Docker: detener servicios'* ]]
bash "$MENU_SCRIPT" 'Docker: detener servicios'

# Existing Docker start keeps its original command and notification.
run_case 0
bash "$MENU_SCRIPT" docker-start
log="$(<"$TEST_DIR/commands")"
assert_contains "pkexec $SYSTEMCTL_BIN start docker.service"
assert_contains 'Servicio iniciado'

printf 'OK: %s cases\n' "$tests"
