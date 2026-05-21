#!/usr/bin/env bash
set -euo pipefail

SUDO="${SUDO-sudo}"

CHECK_ONLY=0
DRY_RUN=0
NO_CONFIRM=0
SKIP_SERVICES=0
PORTAL_BACKEND="auto"

BASE_PACKAGES=(
  obs-studio
  ffmpeg
  v4l-utils
  pavucontrol
  pipewire
  pipewire-pulse
  wireplumber
  xdg-desktop-portal
)

SERVICES=(
  pipewire
  pipewire-pulse
  wireplumber
)

usage() {
  cat <<'EOF'
Usage: setup-obs.sh [options]

Install and set up OBS Studio requirements on Arch Linux.

Options:
  --check-only               Verify requirements only (no changes)
  --dry-run                  Show actions without executing them
  --noconfirm                Pass --noconfirm to pacman install
  --skip-services            Do not modify user services
  --portal-backend VALUE     Portal backend: auto|hyprland|gnome|kde|wlr|gtk|none
  -h, --help                 Show this help
EOF
}

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_cmd() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

run_as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    run_cmd "$@"
    return
  fi

  if [[ -n "${SUDO}" ]]; then
    run_cmd ${SUDO} "$@"
  else
    run_cmd "$@"
  fi
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

detect_portal_backend() {
  local session_type desktop
  session_type="$(lower "${XDG_SESSION_TYPE:-}")"
  desktop="$(lower "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}")"

  if [[ "${session_type}" != "wayland" ]]; then
    printf 'none'
    return
  fi

  case "${desktop}" in
    *hyprland*) printf 'hyprland' ;;
    *gnome*) printf 'gnome' ;;
    *kde*|*plasma*) printf 'kde' ;;
    *sway*|*wlroots*|*river*|*wayfire*) printf 'wlr' ;;
    *) printf 'gtk' ;;
  esac
}

get_portal_packages() {
  local backend="$1"
  case "${backend}" in
    none) ;;
    hyprland) printf '%s\n' xdg-desktop-portal-hyprland ;;
    gnome) printf '%s\n' xdg-desktop-portal-gnome ;;
    kde) printf '%s\n' xdg-desktop-portal-kde ;;
    wlr)
      printf '%s\n' xdg-desktop-portal-wlr
      printf '%s\n' xdg-desktop-portal-gtk
      ;;
    gtk) printf '%s\n' xdg-desktop-portal-gtk ;;
    *) die "Unsupported portal backend: ${backend}" ;;
  esac
}

service_status() {
  local service="$1"
  local enabled active

  enabled="$(systemctl --user is-enabled "${service}" 2>/dev/null || true)"
  active="$(systemctl --user is-active "${service}" 2>/dev/null || true)"

  if [[ -z "${enabled}" ]]; then
    enabled="unknown"
  fi
  if [[ -z "${active}" ]]; then
    active="unknown"
  fi

  printf '%s;%s\n' "${enabled}" "${active}"
}

reconcile_service() {
  local service="$1"
  local enabled="$2"
  local active="$3"

  info "Service ${service}: enabled=${enabled}, active=${active}"

  if [[ "${CHECK_ONLY}" -eq 1 ]]; then
    return
  fi

  case "${enabled}" in
    enabled)
      if [[ "${active}" != "active" ]]; then
        run_cmd systemctl --user start "${service}"
      fi
      ;;
    disabled)
      if [[ "${active}" == "active" ]]; then
        run_cmd systemctl --user enable "${service}"
      else
        run_cmd systemctl --user enable --now "${service}"
      fi
      ;;
    static|indirect|generated)
      if [[ "${active}" != "active" ]]; then
        run_cmd systemctl --user start "${service}"
      fi
      ;;
    masked)
      warn "Service ${service} is masked; skipping auto-fix."
      ;;
    *)
      warn "Service ${service} has unsupported enabled state '${enabled}'."
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --noconfirm)
      NO_CONFIRM=1
      shift
      ;;
    --skip-services)
      SKIP_SERVICES=1
      shift
      ;;
    --portal-backend)
      PORTAL_BACKEND="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "${PORTAL_BACKEND}" ]]; then
  die "--portal-backend requires a value"
fi

if ! have_cmd pacman; then
  die "pacman not found. This script only supports Arch Linux."
fi

if [[ "${PORTAL_BACKEND}" == "auto" ]]; then
  PORTAL_BACKEND="$(detect_portal_backend)"
fi

info "Selected portal backend: ${PORTAL_BACKEND}"

mapfile -t PORTAL_PACKAGES < <(get_portal_packages "${PORTAL_BACKEND}")

REQUIRED_PACKAGES=("${BASE_PACKAGES[@]}")
if [[ ${#PORTAL_PACKAGES[@]} -gt 0 ]]; then
  REQUIRED_PACKAGES+=("${PORTAL_PACKAGES[@]}")
fi

info "Checking required packages..."
MISSING_PACKAGES=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if pacman -Q "${pkg}" >/dev/null 2>&1; then
    info "  [ok] ${pkg}"
  else
    info "  [missing] ${pkg}"
    MISSING_PACKAGES+=("${pkg}")
  fi
done

ISSUES=0
if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
  ISSUES=1
  if [[ "${CHECK_ONLY}" -eq 1 ]]; then
    warn "Missing packages detected in --check-only mode."
  else
    PACMAN_ARGS=(-S --needed)
    if [[ "${NO_CONFIRM}" -eq 1 ]]; then
      PACMAN_ARGS+=(--noconfirm)
    fi
    info "Installing missing packages..."
    run_as_root pacman "${PACMAN_ARGS[@]}" "${MISSING_PACKAGES[@]}"
  fi
else
  info "All required packages are already installed."
fi

if [[ "${SKIP_SERVICES}" -eq 1 ]]; then
  info "Skipping service configuration by request (--skip-services)."
else
  if ! have_cmd systemctl; then
    warn "systemctl not found; skipping user service checks."
    ISSUES=1
  elif ! systemctl --user show-environment >/dev/null 2>&1; then
    warn "Unable to access systemd user session; skipping service checks."
    warn "Run from a user session and retry to configure PipeWire services."
    ISSUES=1
  else
    info "Checking OBS audio services..."
    for service in "${SERVICES[@]}"; do
      status_line="$(service_status "${service}")"
      enabled_state="${status_line%%;*}"
      active_state="${status_line##*;}"

      if [[ "${enabled_state}" != "enabled" || "${active_state}" != "active" ]]; then
        ISSUES=1
      fi

      reconcile_service "${service}" "${enabled_state}" "${active_state}"
    done
  fi
fi

if compgen -G '/dev/video*' >/dev/null; then
  info "Webcam devices detected under /dev/video*."
else
  warn "No /dev/video* devices found. Webcam source may be unavailable."
fi

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  if [[ "${ISSUES}" -eq 0 ]]; then
    info "Check completed successfully. OBS minimum requirements are met."
    exit 0
  fi
  warn "Check completed with issues. Install/setup is still needed."
  exit 1
fi

if [[ "${PORTAL_BACKEND}" != "none" && "$(lower "${XDG_SESSION_TYPE:-}")" == "wayland" ]]; then
  info "If screen capture fails, log out and log back in to refresh portals."
fi

info "OBS setup completed."
