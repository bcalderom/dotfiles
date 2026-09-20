#!/usr/bin/env bash
set -u

HYPRCTL_BIN="${HYPRCTL_BIN:-hyprctl}"
BLUETOOTHCTL_BIN="${BLUETOOTHCTL_BIN:-bluetoothctl}"
ROFI_BIN="${ROFI_BIN:-rofi}"
NOTIFY_SEND_BIN="${NOTIFY_SEND_BIN:-notify-send}"
PKEXEC_BIN="${PKEXEC_BIN:-pkexec}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-/usr/bin/systemctl}"
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

select_action() {
  printf '%s\n' \
    "Teclado: English (US)" \
    "Teclado: Español (ES)" \
    "JBL Charge 5: conectar" \
    "JBL Charge 5: desconectar" \
    "Bluetooth: reiniciar servicio" \
    "Docker: iniciar servicio" \
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
