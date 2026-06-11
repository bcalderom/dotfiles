#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OBS_SCRIPT="${SCRIPT_DIR}/../setup-obs.sh"

if [[ ! -f "${OBS_SCRIPT}" ]]; then
  echo "Missing: ${OBS_SCRIPT}" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

MOCK_BIN="${TMPDIR}/bin"
mkdir -p "${MOCK_BIN}"

PACMAN_LOG="${TMPDIR}/pacman.log"
SYSTEMCTL_LOG="${TMPDIR}/systemctl.log"
: > "${PACMAN_LOG}"
: > "${SYSTEMCTL_LOG}"

export PACMAN_LOG SYSTEMCTL_LOG

cat > "${MOCK_BIN}/pacman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$0" "$@" >> "${PACMAN_LOG}"
printf '\n' >> "${PACMAN_LOG}"

if [[ "${1:-}" == "-Q" ]]; then
  case "${2:-}" in
    obs-studio|xdg-desktop-portal-hyprland)
      exit 1
      ;;
    *)
      exit 0
      ;;
  esac
fi

if [[ "${1:-}" == "-S" ]]; then
  exit 0
fi

echo "Unexpected pacman args: $*" >&2
exit 1
EOF
chmod +x "${MOCK_BIN}/pacman"

cat > "${MOCK_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$0" "$@" >> "${SYSTEMCTL_LOG}"
printf '\n' >> "${SYSTEMCTL_LOG}"

if [[ "${1:-}" == "--user" && "${2:-}" == "show-environment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "--user" && "${2:-}" == "is-enabled" ]]; then
  case "${3:-}" in
    pipewire)
      echo enabled
      exit 0
      ;;
    pipewire-pulse)
      echo enabled
      exit 0
      ;;
    wireplumber)
      echo disabled
      exit 1
      ;;
  esac
fi

if [[ "${1:-}" == "--user" && "${2:-}" == "is-active" ]]; then
  case "${3:-}" in
    pipewire)
      echo active
      exit 0
      ;;
    pipewire-pulse)
      echo inactive
      exit 3
      ;;
    wireplumber)
      echo inactive
      exit 3
      ;;
  esac
fi

if [[ "${1:-}" == "--user" && "${2:-}" == "start" ]]; then
  exit 0
fi

if [[ "${1:-}" == "--user" && "${2:-}" == "enable" ]]; then
  exit 0
fi

echo "Unexpected systemctl args: $*" >&2
exit 1
EOF
chmod +x "${MOCK_BIN}/systemctl"

echo "==> install mode"
PATH="${MOCK_BIN}:${PATH}" \
SUDO="" \
XDG_SESSION_TYPE="wayland" \
XDG_CURRENT_DESKTOP="Hyprland" \
bash "${OBS_SCRIPT}" --noconfirm --portal-backend auto >/dev/null

grep -q -- "-Q obs-studio" "${PACMAN_LOG}"
grep -q -- "-Q xdg-desktop-portal-hyprland" "${PACMAN_LOG}"
grep -q -- "-S --needed --noconfirm obs-studio xdg-desktop-portal-hyprland" "${PACMAN_LOG}"

grep -q -- "--user is-enabled pipewire" "${SYSTEMCTL_LOG}"
grep -q -- "--user is-enabled pipewire-pulse" "${SYSTEMCTL_LOG}"
grep -q -- "--user is-enabled wireplumber" "${SYSTEMCTL_LOG}"
grep -q -- "--user start pipewire-pulse" "${SYSTEMCTL_LOG}"
grep -q -- "--user enable --now wireplumber" "${SYSTEMCTL_LOG}"

if grep -q -- "--user start pipewire " "${SYSTEMCTL_LOG}"; then
  echo "Did not expect start for active pipewire service" >&2
  exit 1
fi

: > "${PACMAN_LOG}"
: > "${SYSTEMCTL_LOG}"

echo "==> check-only mode"
if PATH="${MOCK_BIN}:${PATH}" \
  SUDO="" \
  XDG_SESSION_TYPE="wayland" \
  XDG_CURRENT_DESKTOP="Hyprland" \
  bash "${OBS_SCRIPT}" --check-only --portal-backend auto >/dev/null; then
  echo "Expected --check-only to fail when requirements are missing" >&2
  exit 1
fi

if grep -q -- "-S --needed" "${PACMAN_LOG}"; then
  echo "Did not expect package install in --check-only mode" >&2
  exit 1
fi

if grep -q -- "--user start " "${SYSTEMCTL_LOG}"; then
  echo "Did not expect service start in --check-only mode" >&2
  exit 1
fi

if grep -q -- "--user enable " "${SYSTEMCTL_LOG}"; then
  echo "Did not expect service enable in --check-only mode" >&2
  exit 1
fi

echo "OK"
