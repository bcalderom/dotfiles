#!/usr/bin/env bash
# Post-install bootstrap for Arch. Never partitions disks or copies credentials.
# Defaults reflect shell usage and desktop dependencies; see docs/migration.md.
set -euo pipefail

PKGS_BASE=(
  zsh zsh-completions fzf tmux util-linux ripgrep go-yq jq fd eza neovim
  less tree git stow zoxide man-db openssh rsync curl unzip zip
)
PKGS_DEV=(
  base-devel aws-cli-v2 github-cli lazygit opencode nodejs-lts-jod npm
  pyenv python python-pip uv shellcheck gitleaks
  openssl zlib xz tk sqlite libffi bzip2 readline ncurses
)
PKGS_HYPR=(
  hyprland xdg-desktop-portal-hyprland xdg-desktop-portal wayland
  wayland-protocols wl-clipboard qt5-wayland qt6-wayland grim slurp
  polkit polkit-gnome hypridle hyprlock hyprshot kanshi
)
PKGS_UI=(
  alacritty waybar swaync rofi brightnessctl network-manager-applet
  pavucontrol power-profiles-daemon swappy dolphin obsidian
)
PKGS_AUDIO=(pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils sof-firmware)
PKGS_NETWORK=(networkmanager linux-firmware pciutils)
PKGS_BLUETOOTH=(bluez bluez-utils)
PKGS_FONTS=(
  ttf-ubuntu-mono-nerd ttf-jetbrains-mono-nerd noto-fonts noto-fonts-cjk
  noto-fonts-emoji adobe-source-han-sans-jp-fonts adobe-source-han-serif-jp-fonts
)
PKGS_DOCKER=(docker docker-compose)
PKGS_PRINTING=(cups cups-filters ghostscript avahi nss-mdns sane sane-airscan simple-scan)
PKGS_OBS=(obs-studio)
PKGS_OFFICE=(calibre pandoc-cli thunderbird hunspell-es_es hyphen-es)
PKGS_MEDIA=(mpv ffmpeg)
PKGS_OPTIONAL=(btop htop bind tcpdump stress-ng tldr)
# CPU microcode and GPU drivers are independent (including hybrid machines).
PKGS_AMD=(amd-ucode)
PKGS_INTEL=(intel-ucode)
PKGS_AMD_GPU=(linux-firmware-amdgpu mesa vulkan-radeon)
PKGS_INTEL_GPU=(linux-firmware-intel mesa intel-media-driver vulkan-intel)

declare -A AUR_GROUPS=(
  [dev]="sesh-bin"
  [ui]="brave-bin"
  [keyboard]="kanata"
  [vpn]="nordvpn-bin netbird"
  [office]="onlyoffice-bin marktext-bin"
  [comms]="teams-for-linux zoom"
  [media]="spotify"
)
ALL_GROUPS=(
  base dev hypr ui audio network bluetooth fonts keyboard vpn docker printing
  obs office comms media optional amd intel amd-gpu intel-gpu
)
DEFAULT_GROUPS=(base dev hypr ui audio network bluetooth fonts keyboard vpn)
declare -A VALID_GROUPS=() SELECTED=() SEEN=()
for group in "${ALL_GROUPS[@]}"; do VALID_GROUPS["$group"]=1; done

DRY_RUN=0
CHECK_ONLY=0
DO_UPDATE=1
ENABLE_SERVICES=0
STOW=0
CPU=auto
GPU=auto
AUR_HELPER=none
ONLY_GROUPS=()
EXTRA_GROUPS=()
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: bash setup.sh [options]
Post-install setup; does not install Arch, format disks, or restore private data.

  --dry-run             Show changes without installing or changing anything
  --check               Report missing selected packages; exit 1 if incomplete
  --no-update           Use existing sync DBs; only install missing packages
                        Only use immediately after a successful full upgrade
  --only a,b,c          Select exactly these groups (no automatic hardware groups)
  --with a,b,c          Add groups to the default selection or to --only
  --cpu auto|amd|intel|none
  --gpu auto|amd|intel|none
                        Detect CPU and PCI display GPUs independently by default
                        NVIDIA needs a separate, hardware-specific driver review
  --aur none|yay|paru    Use an ALREADY installed helper as a normal user
                        Default: report pending AUR packages, do not install them
  --enable-services     Enable selected NetworkManager/Bluetooth/power/time units
                        Does not start services; never enables SSH, VPN or Docker
  --stow                Simulate, then link this checkout to HOME; no --adopt
  --list-groups         List all groups and defaults
  -h, --help            Show help

No non-interactive confirmation flags are passed to pacman or AUR helpers.
--check is read-only; with --stow/--enable-services it also checks those actions.
Authentication, plugins, Python versions, printer drivers and host settings need
the final manual steps documented in docs/migration.md.
EOF
}

die() { echo "Error: $*" >&2; exit 2; }

require_value() {
  [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 requires a value"
}

parse_groups() {
  local value="$1" group
  local -n result="$2"
  [[ "$value" =~ ^[a-z]+(-gpu)?(,[a-z]+(-gpu)?)*$ ]] || die "Invalid group list: $value"
  local -a parsed=()
  IFS=',' read -r -a parsed <<< "$value"
  for group in "${parsed[@]}"; do
    [[ "$group" =~ ^[a-z]+(-gpu)?$ && -n "${VALID_GROUPS[$group]+x}" ]] || die "Unknown group: $group"
    result+=("$group")
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --check) CHECK_ONLY=1; shift ;;
    --no-update) DO_UPDATE=0; shift ;;
    --enable-services) ENABLE_SERVICES=1; shift ;;
    --stow) STOW=1; shift ;;
    --only|--with)
      require_value "$@"
      if [[ "$1" == --only ]]; then
        parse_groups "$2" ONLY_GROUPS
      else
        parse_groups "$2" EXTRA_GROUPS
      fi
      shift 2 ;;
    --cpu|--gpu)
      require_value "$@"
      case "$2" in auto|amd|intel|none) ;; *) die "Invalid hardware profile: $2" ;; esac
      if [[ "$1" == --cpu ]]; then CPU="$2"; else GPU="$2"; fi
      shift 2 ;;
    --aur)
      require_value "$@"
      case "$2" in none|yay|paru) AUR_HELPER="$2" ;; *) die "Invalid AUR helper: $2" ;; esac
      shift 2 ;;
    --list-groups)
      echo "Groups: ${ALL_GROUPS[*]}"
      echo "Defaults: ${DEFAULT_GROUPS[*]} + detected CPU/GPU"
      exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [[ ${#ONLY_GROUPS[@]} -gt 0 ]]; then
  [[ "$CPU" == auto && "$GPU" == auto ]] || die "Use hardware group names with --only, not --cpu/--gpu"
  for group in "${ONLY_GROUPS[@]}"; do SELECTED["$group"]=1; done
else
  for group in "${DEFAULT_GROUPS[@]}"; do SELECTED["$group"]=1; done
  if [[ "$CPU" == auto ]]; then
    cpu_info="$(LC_ALL=C lscpu 2>/dev/null || true)"
    case "$cpu_info" in
      *AuthenticAMD*) CPU=amd ;;
      *GenuineIntel*) CPU=intel ;;
      *) CPU=none; echo "Warning: CPU not detected; select --cpu explicitly." >&2 ;;
    esac
  fi
  if [[ "$CPU" != none ]]; then SELECTED["$CPU"]=1; fi
  if [[ "$GPU" == auto ]]; then
    if command -v lspci >/dev/null 2>&1; then
      pci_info="$(lspci -n)"
      while IFS= read -r line; do
        if [[ "$line" =~ [[:space:]]03[[:xdigit:]]{2}:[[:space:]]([[:xdigit:]]{4}): ]]; then
          case "${BASH_REMATCH[1]}" in
            1002) SELECTED[amd-gpu]=1 ;;
            8086) SELECTED[intel-gpu]=1 ;;
            10de) echo "Warning: NVIDIA detected; review its drivers separately before starting Hyprland." >&2 ;;
          esac
        fi
      done <<< "$pci_info"
    else
      echo "Warning: lspci unavailable; select --gpu explicitly after checking the GPU." >&2
    fi
  elif [[ "$GPU" != none ]]; then
    SELECTED["$GPU-gpu"]=1
  fi
fi
for group in "${EXTRA_GROUPS[@]}"; do SELECTED["$group"]=1; done
[[ -z "${SELECTED[amd]+x}" || -z "${SELECTED[intel]+x}" ]] || die "Select only one CPU microcode group"

command -v pacman >/dev/null 2>&1 || die "Run this script on an installed Arch Linux system"
if [[ $DRY_RUN -eq 0 && $CHECK_ONLY -eq 0 ]]; then
  if [[ "$AUR_HELPER" != none || $STOW -eq 1 ]]; then
    [[ $EUID -ne 0 ]] || die "Run AUR and dotfile setup as your normal user, not root"
  fi
fi

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '==> Would run:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

run_as_root() {
  if [[ $EUID -eq 0 ]]; then run "$@"; else run sudo "$@"; fi
}

OFFICIAL=()
AUR=()
for group in "${ALL_GROUPS[@]}"; do
  [[ -n "${SELECTED[$group]+x}" ]] || continue
  echo "==> Group: $group"
  case "$group" in
    base) packages=("${PKGS_BASE[@]}") ;;
    dev) packages=("${PKGS_DEV[@]}") ;;
    hypr) packages=("${PKGS_HYPR[@]}") ;;
    ui) packages=("${PKGS_UI[@]}") ;;
    audio) packages=("${PKGS_AUDIO[@]}") ;;
    network) packages=("${PKGS_NETWORK[@]}") ;;
    bluetooth) packages=("${PKGS_BLUETOOTH[@]}") ;;
    fonts) packages=("${PKGS_FONTS[@]}") ;;
    docker) packages=("${PKGS_DOCKER[@]}") ;;
    printing) packages=("${PKGS_PRINTING[@]}") ;;
    obs) packages=("${PKGS_OBS[@]}") ;;
    office) packages=("${PKGS_OFFICE[@]}") ;;
    media) packages=("${PKGS_MEDIA[@]}") ;;
    optional) packages=("${PKGS_OPTIONAL[@]}") ;;
    amd) packages=("${PKGS_AMD[@]}") ;;
    intel) packages=("${PKGS_INTEL[@]}") ;;
    amd-gpu) packages=("${PKGS_AMD_GPU[@]}") ;;
    intel-gpu) packages=("${PKGS_INTEL_GPU[@]}") ;;
    keyboard|vpn|comms) packages=() ;;
  esac
  for package in "${packages[@]}"; do
    [[ -z "${SEEN[$package]+x}" ]] || continue
    OFFICIAL+=("$package"); SEEN["$package"]=1
  done
  aur_packages=()
  read -r -a aur_packages <<< "${AUR_GROUPS[$group]-}"
  for package in "${aur_packages[@]}"; do
    [[ -z "${SEEN[$package]+x}" ]] || continue
    # A package may have moved from AUR to an enabled official repository.
    if pacman -Si "$package" &>/dev/null; then
      OFFICIAL+=("$package")
    else
      AUR+=("$package")
    fi
    SEEN["$package"]=1
  done
done

MISSING_OFFICIAL=()
MISSING_AUR=()
for package in "${OFFICIAL[@]}"; do
  if ! pacman -Q "$package" &>/dev/null; then MISSING_OFFICIAL+=("$package"); fi
done
for package in "${AUR[@]}"; do
  if ! pacman -Q "$package" &>/dev/null; then MISSING_AUR+=("$package"); fi
done
echo "Missing official packages (${#MISSING_OFFICIAL[@]}): ${MISSING_OFFICIAL[*]}"
echo "Missing AUR packages (${#MISSING_AUR[@]}): ${MISSING_AUR[*]}"

SERVICES=()
if [[ -n "${SELECTED[network]+x}" ]]; then SERVICES+=(NetworkManager.service systemd-timesyncd.service); fi
if [[ -n "${SELECTED[bluetooth]+x}" ]]; then SERVICES+=(bluetooth.service); fi
if [[ -n "${SELECTED[ui]+x}" ]]; then SERVICES+=(power-profiles-daemon.service); fi

stow_dotfiles() {
  local -a args=(
    --no-folding --dir "$REPO_DIR" --target "$HOME"
    --ignore '(^|/)[^/]+\.(wants|requires)(/|$)'
    --ignore '^(docs|setup\.sh|\.ruff_cache)$' .
  )
  # A real simulation must succeed before linking; never use --adopt/--override.
  run stow --simulate --verbose "${args[@]}" || return $?
  if [[ $CHECK_ONLY -eq 0 ]]; then run stow --verbose "${args[@]}"; fi
}

if [[ $CHECK_ONLY -eq 1 ]]; then
  incomplete=0
  if [[ ${#MISSING_OFFICIAL[@]} -gt 0 || ${#MISSING_AUR[@]} -gt 0 ]]; then incomplete=1; fi
  if [[ $ENABLE_SERVICES -eq 1 ]]; then
    for service in "${SERVICES[@]}"; do
      if ! systemctl is-enabled --quiet "$service"; then
        echo "Not enabled: $service"; incomplete=1
      fi
    done
  fi
  # --check takes precedence over --dry-run: actually perform read-only checks.
  DRY_RUN=0
  if [[ $STOW -eq 1 ]]; then
    if ! command -v stow >/dev/null 2>&1; then
      echo "Cannot check dotfiles: stow is not installed"; incomplete=1
    elif ! stow_dotfiles; then
      incomplete=1
    fi
  fi
  exit "$incomplete"
fi

if [[ ${#MISSING_AUR[@]} -gt 0 && "$AUR_HELPER" != none ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    command -v "$AUR_HELPER" >/dev/null 2>&1 || die "Install and review $AUR_HELPER first; see docs/migration.md"
  fi
fi

# One full transaction avoids refreshing databases without upgrading the system.
if [[ $DO_UPDATE -eq 1 ]]; then
  run_as_root pacman -Syu --needed "${OFFICIAL[@]}"
elif [[ ${#MISSING_OFFICIAL[@]} -gt 0 ]]; then
  run_as_root pacman -S --needed "${MISSING_OFFICIAL[@]}"
fi

pending=0
if [[ ${#MISSING_AUR[@]} -gt 0 ]]; then
  if [[ "$AUR_HELPER" == none ]]; then
    echo "Pending manual AUR review/install: ${MISSING_AUR[*]}"
    echo "Rerun as a normal user with --aur yay (or --aur paru) after reviewing the helper."
    pending=1
  else
    run "$AUR_HELPER" -S --needed "${MISSING_AUR[@]}"
  fi
fi
if [[ $ENABLE_SERVICES -eq 1 && ${#SERVICES[@]} -gt 0 ]]; then
  run_as_root systemctl enable "${SERVICES[@]}"
fi
if [[ $STOW -eq 1 ]]; then stow_dotfiles; fi

echo "No services started; no shell, disk, authentication or private data changed."
echo "Finish plugins, Python environments and host-specific settings using docs/migration.md."
if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry run only; nothing changed."
  exit 0
fi
if [[ $pending -eq 1 ]]; then
  echo "Setup incomplete: AUR packages remain pending."
  exit 1
fi
echo "Selected package setup completed."
