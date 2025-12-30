#!/usr/bin/env bash
# Arch Linux package bootstrapper
# - Checks what's already installed
# - Installs only missing packages
# - Keeps packages categorized for maintainability
#
# Usage:
#   ./install-packages.sh
#   ./install-packages.sh --dry-run
#   ./install-packages.sh --no-update
#   ./install-packages.sh --only base,hypr,fonts
#
# Notes:
# - Assumes official repos (pacman). No AUR handling here.
# - Uses: pacman -Qi for installed checks.

set -euo pipefail

############################
# Config: package groups
############################

# Shell / CLI essentials
PKGS_BASE=(
  zsh
  zsh-completions
  fzf
  npm
  unzip
  tmux
  ripgrep
  fd
  neovim
  less
  tree
  git
  stow
  zoxide
)

# Wayland / Hyprland desktop stack
PKGS_HYPR=(
  hyprland
  xdg-desktop-portal-hyprland
  xdg-desktop-portal
  wayland
  wayland-protocols
  wl-clipboard
  qt5-wayland
  qt6-wayland
  grim
  slurp
  polkit
  polkit-gnome
)

# UI / desktop utilities
PKGS_UI=(
  alacritty
  waybar
  mako
  rofi
  brightnessctl
  pavucontrol
  swappy
  obsidian
)

# Media / file tools
PKGS_MEDIA=(
  mpv
  ffmpeg
  yazi
)

# Bluetooth
PKGS_BLUETOOTH=(
  bluez
  bluez-utils
)

# Fonts
PKGS_FONTS=(
  ttf-ubuntu-mono-nerd
  ttf-jetbrains-mono-nerd
  adobe-source-han-sans-jp-fonts
  adobe-source-han-serif-jp-fonts
  noto-fonts-cjk
  noto-fonts-emoji
)

# Optional extras (commented in your input)
PKGS_OPTIONAL=(
  # tldr
  # thefuck
  # bat
  # syncthing
)

# Intel drivers
PKGS_INTEL=(
  linux-firmware-intel
  intel-media-driver
  libva-utils
  intel-ucode
)

############################
# CLI args
############################
DRY_RUN=0
DO_UPDATE=1
ONLY_GROUPS=()

usage() {
  cat <<'EOF'
Arch Linux package bootstrapper

Options:
  --dry-run        Show what would be installed, don't install
  --no-update      Skip pacman -Syu
  --only a,b,c     Install only these groups (comma-separated)
                  Groups: base,hypr,ui,media,bluetooth,fonts,optional
  -h, --help       Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --dry-run) DRY_RUN=1; shift ;;
    --no-update) DO_UPDATE=0; shift ;;
    --only)
      [[ $# -lt 2 ]] && { echo "Error: --only requires a value"; exit 2; }
      IFS=',' read -r -a ONLY_GROUPS <<< "${2}"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

############################
# Helpers
############################

need_root=0
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  need_root=1
fi

run_as_root() {
  if [[ $need_root -eq 1 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

is_installed() {
  # pacman -Qi returns 0 if installed, non-zero otherwise
  pacman -Qi "$1" &>/dev/null
}

print_group() {
  local name="$1"; shift
  local -a pkgs=("$@")

  echo
  echo "==> Group: ${name}"
  echo "    Packages: ${#pkgs[@]}"
}

############################
# Select groups
############################
declare -A GROUP_MAP=(
  [base]=1
  [hypr]=1
  [ui]=1
  [media]=1
  [bluetooth]=1
  [fonts]=1
  [optional]=1
  [intel]=1
)

should_include_group() {
  local g="$1"
  if [[ ${#ONLY_GROUPS[@]} -eq 0 ]]; then
    return 0
  fi
  local x
  for x in "${ONLY_GROUPS[@]}"; do
    if [[ "$x" == "$g" ]]; then
      return 0
    fi
  done
  return 1
}

get_group_pkgs() {
  local g="$1"
  case "$g" in
    base)      printf '%s\n' "${PKGS_BASE[@]}" ;;
    hypr)      printf '%s\n' "${PKGS_HYPR[@]}" ;;
    ui)        printf '%s\n' "${PKGS_UI[@]}" ;;
    media)     printf '%s\n' "${PKGS_MEDIA[@]}" ;;
    bluetooth) printf '%s\n' "${PKGS_BLUETOOTH[@]}" ;;
    fonts)     printf '%s\n' "${PKGS_FONTS[@]}" ;;
    optional)  printf '%s\n' "${PKGS_OPTIONAL[@]}" ;;
    intel)     printf '%s\n' "${PKGS_INTEL[@]}" ;;
    *)
      echo "Error: unknown group '$g'" >&2
      exit 2
      ;;
  esac
}

validate_only_groups() {
  local g
  for g in "${ONLY_GROUPS[@]}"; do
    if [[ -z "${GROUP_MAP[$g]+x}" ]]; then
      echo "Error: unknown group in --only: '$g'" >&2
      echo "Valid groups: base,hypr,ui,media,bluetooth,fonts,optional,intel" >&2
      exit 2
    fi
  done
}

validate_only_groups

############################
# Main
############################

echo "Arch package bootstrapper"
if [[ ${#ONLY_GROUPS[@]} -gt 0 ]]; then
  echo "Selected groups: ${ONLY_GROUPS[*]}"
else
  echo "Selected groups: all"
fi
[[ $DRY_RUN -eq 1 ]] && echo "Mode: DRY RUN"
[[ $DO_UPDATE -eq 0 ]] && echo "Update: skipped"

# Update system first (optional)
if [[ $DO_UPDATE -eq 1 ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo
    echo "==> Would run: sudo pacman -Syu"
  else
    echo
    echo "==> Updating system: pacman -Syu"
    run_as_root pacman -Syu --noconfirm
  fi
fi

# Compute missing packages per group (and overall)
declare -a TO_INSTALL=()
declare -A MISSING_BY_GROUP=()

for group in base hypr ui media bluetooth fonts optional intel; do
  if ! should_include_group "$group"; then
    continue
  fi

  mapfile -t pkgs < <(get_group_pkgs "$group")

  # Skip empty groups cleanly
  if [[ ${#pkgs[@]} -eq 0 ]]; then
    continue
  fi

  print_group "$group" "${pkgs[@]}"

  missing=()
  for p in "${pkgs[@]}"; do
    if is_installed "$p"; then
      echo "    [OK]   $p"
    else
      echo "    [MISS] $p"
      missing+=("$p")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    MISSING_BY_GROUP["$group"]="${missing[*]}"
    TO_INSTALL+=("${missing[@]}")
  fi
done

# De-duplicate (just in case)
if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
  mapfile -t TO_INSTALL < <(printf '%s\n' "${TO_INSTALL[@]}" | awk '!seen[$0]++')
fi

echo
if [[ ${#TO_INSTALL[@]} -eq 0 ]]; then
  echo "✅ All selected packages are already installed."
  exit 0
fi

echo "==> Missing packages total: ${#TO_INSTALL[@]}"
printf '    %s\n' "${TO_INSTALL[@]}"

# Install missing
if [[ $DRY_RUN -eq 1 ]]; then
  echo
  echo "==> Would run: sudo pacman -S --needed ${TO_INSTALL[*]}"
  exit 0
fi

echo
echo "==> Installing missing packages..."
run_as_root pacman -S --needed --noconfirm "${TO_INSTALL[@]}"

echo
echo "✅ Done."
