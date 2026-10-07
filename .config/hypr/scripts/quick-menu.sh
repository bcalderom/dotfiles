#!/usr/bin/env bash
set -u

HYPRCTL_BIN="${HYPRCTL_BIN:-hyprctl}"
BLUETOOTHCTL_BIN="${BLUETOOTHCTL_BIN:-bluetoothctl}"
ROFI_BIN="${ROFI_BIN:-rofi}"
NOTIFY_SEND_BIN="${NOTIFY_SEND_BIN:-notify-send}"
PKEXEC_BIN="${PKEXEC_BIN:-pkexec}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-/usr/bin/systemctl}"
DOCKER_BIN="${DOCKER_BIN:-/usr/bin/docker}"
PSVC_BIN="${PSVC_BIN:-${HOME}/scripts/bin/psvc}"
JBL_MAC="10:28:74:E6:AC:EC"
NOTIFICATION_ID=4901

notify_success() {
  "$NOTIFY_SEND_BIN" -a "Menú rápido" -r "$NOTIFICATION_ID" -i "$1" "$2" "$3"
}

notify_failure() {
  "$NOTIFY_SEND_BIN" -a "Menú rápido" -r "$NOTIFICATION_ID" -u critical -i dialog-error \
    "No se pudo completar la acción" "${1:-Error desconocido}"
}

run_action() {
  local icon="$1" title="$2" message="$3" output
  shift 3

  if output="$("$@" 2>&1)"; then
    case "$output" in
      *[Ee]rror*|*[Ff]ailed*|*"can't"*)
        notify_failure "$output"
        return 1
        ;;
    esac
    notify_success "$icon" "$title" "$message"
    return 0
  fi

  notify_failure "$output"
  return 1
}

docker_local() {
  env -u DOCKER_CONTEXT -u DOCKER_HOST -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH \
    "$DOCKER_BIN" --host unix:///run/docker.sock "$@"
}

docker_service_state() {
  local state
  if ! state="$("$SYSTEMCTL_BIN" show --property=ActiveState --value "$1" 2>&1)"; then
    notify_failure "No se pudo consultar $1: $state"
    return 1
  fi
  case "$state" in
    active|inactive|failed) printf '%s\n' "$state" ;;
    *)
      notify_failure "$1 tiene un estado inesperado: $state. Vuelve a intentarlo cuando termine la transición."
      return 1
      ;;
  esac
}

docker_containers() {
  local state output
  state="$(docker_service_state docker.service)" || return 1
  if [[ "$state" != active ]]; then
    notify_failure "Docker no está activo; no se pueden comprobar los contenedores sin iniciar el servicio."
    return 1
  fi
  if ! output="$(timeout 10s env -u DOCKER_CONTEXT -u DOCKER_HOST \
    -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH "$DOCKER_BIN" \
    --host unix:///run/docker.sock ps --no-trunc --format '{{.ID}} {{.Names}}' 2>&1)"; then
    notify_failure "No se pudieron consultar los contenedores locales: $output"
    return 1
  fi
  printf '%s' "$output"
}

stop_docker_services() {
  local unit state daemon_state="" containerd_state="" any_active=0
  local containers current id name choice output message count=0
  local -a ids=()
  local -A approved=()
  local -a units=(docker.socket docker.service containerd.service)

  for unit in "${units[@]}"; do
    state="$(docker_service_state "$unit")" || return 1
    [[ "$state" == active ]] && any_active=1
    [[ "$unit" == docker.service ]] && daemon_state="$state"
    [[ "$unit" == containerd.service ]] && containerd_state="$state"
  done
  if (( ! any_active )); then
    notify_success docker "Servicios Docker" "Los servicios de Docker ya están detenidos"
    return 0
  fi

  if [[ "$daemon_state" == active ]]; then
    containers="$(docker_containers)" || return 1
    message=""
    while read -r id name; do
      [[ -n "$id" ]] || continue
      approved["$id"]=1
      (( count += 1 ))
      if (( count <= 5 )); then message+=$'\n'"• $name"; fi
    done <<< "$containers"
    if (( count > 0 )); then
      if (( count > 5 )); then message+=$'\n'"… y $((count - 5)) más"; fi
      message="Hay $count contenedores activos:$message"$'\n\n'"Se detendrán los contenedores y Docker, su socket y containerd. ¿Continuar?"
      choice="$(printf '%s\n' "Cancelar" "Detener" |
        "$ROFI_BIN" -dmenu -i -no-custom -selected-row 0 -p "Detener Docker" -mesg "$message")" || return 0
      [[ "$choice" == "Detener" ]] || return 0
    fi

    current="$(docker_containers)" || return 1
    while read -r id name; do
      [[ -n "$id" ]] || continue
      if [[ "${approved[$id]:-}" != 1 ]]; then
        notify_failure "Aparecieron nuevos contenedores activos ($name). Vuelve a seleccionar la acción para confirmarlos."
        return 1
      fi
      ids+=("$id")
    done <<< "$current"
    if (( ${#ids[@]} > 0 )); then
      if ! output="$(docker_local stop --timeout 30 "${ids[@]}" 2>&1)"; then
        notify_failure "No se pudieron detener todos los contenedores; los servicios no se han detenido: $output"
        return 1
      fi
    fi
    current="$(docker_containers)" || return 1
    if [[ -n "$current" ]]; then
      notify_failure "Todavía hay contenedores activos; los servicios no se han detenido. Vuelve a seleccionar la acción."
      return 1
    fi
  elif [[ "$containerd_state" == active ]]; then
    notify_failure "containerd está activo pero Docker no lo está. No se puede verificar si quedan contenedores; los servicios no se han detenido."
    return 1
  fi

  if ! output="$("$PKEXEC_BIN" "$SYSTEMCTL_BIN" stop "${units[@]}" 2>&1)"; then
    notify_failure "No se pudieron detener los servicios de Docker: $output"
    return 1
  fi
  for unit in "${units[@]}"; do
    state="$(docker_service_state "$unit")" || return 1
    if [[ "$state" != inactive ]]; then
      notify_failure "$unit no quedó detenido (estado: $state)."
      return 1
    fi
  done
  notify_success docker "Servicios Docker" "Docker, su socket y containerd detenidos"
}

select_action() {
  printf '%s\n' \
    "Teclado: English (US)" \
    "Teclado: Español (ES)" \
    "JBL Charge 5: conectar" \
    "JBL Charge 5: desconectar" \
    "Bluetooth: reiniciar servicio" \
    "Docker: iniciar servicio" \
    "Docker: detener servicios" \
    "Impresión: iniciar servicio" |
    "$ROFI_BIN" -dmenu -i -p "Acción rápida"
}

action="${1:-}"
if [[ -z "$action" ]]; then
  action="$(select_action)" || exit 0
fi

case "$action" in
  keyboard-us|"Teclado: English (US)")
    run_action input-keyboard "Distribución del teclado" "English (US)" \
      "$HYPRCTL_BIN" switchxkblayout all 0
    ;;
  keyboard-es|"Teclado: Español (ES)")
    run_action input-keyboard "Distribución del teclado" "Español (ES)" \
      "$HYPRCTL_BIN" switchxkblayout all 1
    ;;
  jbl-connect|"JBL Charge 5: conectar")
    run_action audio-speakers "JBL Charge 5" "Dispositivo conectado" \
      "$BLUETOOTHCTL_BIN" connect "$JBL_MAC"
    ;;
  jbl-disconnect|"JBL Charge 5: desconectar")
    run_action audio-speakers "JBL Charge 5" "Dispositivo desconectado" \
      "$BLUETOOTHCTL_BIN" disconnect "$JBL_MAC"
    ;;
  bluetooth-restart|"Bluetooth: reiniciar servicio")
    run_action bluetooth-active "Servicio Bluetooth" "Servicio reiniciado" \
      "$PKEXEC_BIN" "$SYSTEMCTL_BIN" restart bluetooth.service
    ;;
  docker-start|"Docker: iniciar servicio")
    run_action docker "Servicio Docker" "Servicio iniciado" \
      "$PKEXEC_BIN" "$SYSTEMCTL_BIN" start docker.service
    ;;
  docker-stop|"Docker: detener servicios")
    stop_docker_services
    ;;
  printing-start|"Impresión: iniciar servicio")
    run_action printer "Servicio de impresión" "CUPS y Avahi iniciados" \
      "$PKEXEC_BIN" "$PSVC_BIN" start
    ;;
  "")
    exit 0
    ;;
  *)
    notify_failure "Acción desconocida: $action"
    exit 2
    ;;
esac
