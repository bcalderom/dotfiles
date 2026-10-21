#!/usr/bin/env bash
# Post-install bootstrap for Arch. Private config migration is explicitly opt-in.
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
  pavucontrol power-profiles-daemon swappy nautilus gvfs gsimplecal obsidian chromium
  python xdg-user-dirs xdg-desktop-portal-gtk
)
PKGS_AUDIO=(pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils sof-firmware)
PKGS_NETWORK=(networkmanager linux-firmware pciutils openbsd-netcat)
PKGS_VPN=(python)
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
  [dev]="sesh-bin heidisql-qt6"
  [ui]="brave-bin"
  [keyboard]="kanata"
  [vpn]="nordvpn-bin netbird netbird-ui-bin"
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
DEPLOY_KANATA=0
CONFIGURE_LID=0
CONFIGURE_DESKTOP=0
CONFIGURE_NETBIRD=0
NETBIRD_MANAGEMENT_URL="https://api.netbird.io:443"
NETBIRD_HOSTNAME=""
NETBIRD_OPTIONS=0
STOW=0
CPU=auto
GPU=auto
AUR_HELPER=none
ONLY_GROUPS=()
EXTRA_GROUPS=()
CONFIG_SOURCE=""
CONFIG_APPS=""
CONFIG_SSH_CONTROL_PATH=""
CONFIG_SSH_KEYS=()
INCLUDE_PRIVATE_CONFIGS=0
CONFIGS_ONLY=0
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: bash setup.sh [options]
Post-install setup; does not install Arch or format disks.

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
  --configure-desktop   Set up Files bookmarks/dark mode and Monday-first calendar
                        Requires ui; normal user; no application/service restart
  --configure-netbird   Enable/start NetBird and connect through interactive SSO
                        Requires vpn; never copies peer keys or enables NetBird SSH
  --netbird-management-url URL
                        HTTPS service origin (default: https://api.netbird.io:443)
  --netbird-hostname NAME
                        Optional hostname for first registration; never renames a peer
  --deploy-kanata       Validate/deploy Kanata; explicitly enable and restart it
                        Requires the keyboard group; normal user, not root
  --configure-lid       Stay awake on lid close, on battery/AC/dock; detect sensor
                        and backlight, reload logind and restart lid coordinator
                        Requires hypr; never restarts Hyprland or logind
  --copy-app-configs-from HOME_DIR|USER@HOST
                        Copy selected app settings, never the entire HOME
  --config-apps a,b      Required: onlyoffice,marktext,heidisql,chromium,brave
                        teams-for-linux,thunderbird,spotify,opencode (v2 settings)
                        ssh (config/known_hosts; private identities require --ssh-key)
  --ssh-key BASENAME    Explicit SSH identity to migrate, e.g. id_rsa; repeatable
                        Requires --config-apps ssh, private consent and confirmation
  --config-ssh-control-path PATH
                        Optional existing SSH control socket for remote source
  --include-private-configs
                        Authorize selected settings that may contain credentials
  --configs-only        Only migrate settings; no packages, services or Stow
  --list-groups         List all groups and defaults
  -h, --help            Show help

No non-interactive confirmation flags are passed to pacman or AUR helpers.
--check is read-only; with --stow/--enable-services it also checks those actions.
Hardware deployment is opt-in; --dry-run previews it and --check checks it only.
Config migration checks that apps are closed, stages/verifies the copy and backs
up existing settings. Real copying requires private-data consent and a TTY prompt.
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
    --deploy-kanata) DEPLOY_KANATA=1; shift ;;
    --configure-lid) CONFIGURE_LID=1; shift ;;
    --configure-desktop) CONFIGURE_DESKTOP=1; shift ;;
    --configure-netbird) CONFIGURE_NETBIRD=1; shift ;;
    --stow) STOW=1; shift ;;
    --configs-only) CONFIGS_ONLY=1; shift ;;
    --include-private-configs) INCLUDE_PRIVATE_CONFIGS=1; shift ;;
    --copy-app-configs-from|--config-apps|--config-ssh-control-path|--ssh-key|--netbird-management-url|--netbird-hostname)
      require_value "$@"
      case "$1" in
        --copy-app-configs-from) CONFIG_SOURCE="$2" ;;
        --config-apps) CONFIG_APPS="$2" ;;
        --config-ssh-control-path) CONFIG_SSH_CONTROL_PATH="$2" ;;
        --ssh-key) CONFIG_SSH_KEYS+=("$2") ;;
        --netbird-management-url) NETBIRD_MANAGEMENT_URL="$2"; NETBIRD_OPTIONS=1 ;;
        --netbird-hostname) NETBIRD_HOSTNAME="$2"; NETBIRD_OPTIONS=1 ;;
      esac
      shift 2 ;;
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

copy_app_configs() {
  local preview="${1:-0}" helper="$REPO_DIR/scripts/system/migrate-app-configs/migrate_app_configs.py"
  local -a args=(--source "$CONFIG_SOURCE" --apps "$CONFIG_APPS")
  command -v python3 >/dev/null 2>&1 || die "Config migration requires python3"
  [[ -f "$helper" ]] || die "Missing config migration helper: $helper"
  if [[ $preview -eq 1 || $DRY_RUN -eq 1 || $CHECK_ONLY -eq 1 ]]; then args+=(--dry-run); fi
  if [[ $INCLUDE_PRIVATE_CONFIGS -eq 1 ]]; then args+=(--include-private-configs); fi
  if [[ -n "$CONFIG_SSH_CONTROL_PATH" ]]; then args+=(--ssh-control-path "$CONFIG_SSH_CONTROL_PATH"); fi
  for key in "${CONFIG_SSH_KEYS[@]}"; do args+=(--ssh-key "$key"); done
  python3 "$helper" "${args[@]}"
}

if [[ -n "$CONFIG_SOURCE" ]]; then
  [[ -n "$CONFIG_APPS" ]] || die "--copy-app-configs-from requires --config-apps"
  if [[ $DRY_RUN -eq 0 && $CHECK_ONLY -eq 0 ]]; then
    [[ $EUID -ne 0 ]] || die "Migrate app configs as your normal user, not root"
    [[ $INCLUDE_PRIVATE_CONFIGS -eq 1 ]] || die "Real copying requires --include-private-configs"
  fi
elif [[ -n "$CONFIG_APPS" || -n "$CONFIG_SSH_CONTROL_PATH" || ${#CONFIG_SSH_KEYS[@]} -gt 0 || $INCLUDE_PRIVATE_CONFIGS -eq 1 || $CONFIGS_ONLY -eq 1 ]]; then
  die "Config migration options require --copy-app-configs-from"
fi
if [[ ${#CONFIG_SSH_KEYS[@]} -gt 0 ]]; then
  [[ ",$CONFIG_APPS," == *,ssh,* ]] || die "--ssh-key requires --config-apps ssh"
  for key in "${CONFIG_SSH_KEYS[@]}"; do
    [[ "$key" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "SSH identities must be explicit basenames, not paths or wildcards"
    case "$key" in config|known_hosts|known_hosts.old|authorized_keys|*.pub) die "Select a private-key basename with --ssh-key" ;; esac
  done
fi
[[ $NETBIRD_OPTIONS -eq 0 || $CONFIGURE_NETBIRD -eq 1 ]] || die "NetBird options require --configure-netbird"
if [[ $CONFIGURE_NETBIRD -eq 1 ]]; then
  [[ "$NETBIRD_MANAGEMENT_URL" =~ ^https://[^/@?#[:space:]]+/?$ ]] || die "NetBird requires an HTTPS origin without credentials or query parameters"
  [[ -z "$NETBIRD_HOSTNAME" || "$NETBIRD_HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || die "Invalid NetBird hostname"
fi
if [[ $CONFIGS_ONLY -eq 1 ]]; then
  [[ $ENABLE_SERVICES -eq 0 && $STOW -eq 0 && $DEPLOY_KANATA -eq 0 && $CONFIGURE_LID -eq 0 && $CONFIGURE_DESKTOP -eq 0 && $CONFIGURE_NETBIRD -eq 0 && ${#ONLY_GROUPS[@]} -eq 0 && ${#EXTRA_GROUPS[@]} -eq 0 && "$CPU" == auto && "$GPU" == auto && "$AUR_HELPER" == none ]] || die "--configs-only cannot be combined with package, service or Stow selection"
  copy_app_configs
  exit $?
fi
# Catch unsafe config requests before any package/service changes.
if [[ -n "$CONFIG_SOURCE" && $CHECK_ONLY -eq 0 ]]; then copy_app_configs 1; fi

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
KANATA_HELPER="$REPO_DIR/scripts/keyboard/kanata-deploy/kanata-deploy.sh"
LID_HELPER="$REPO_DIR/scripts/desktop/hypr-lid-deploy/configure-host.sh"
DESKTOP_HELPER="$REPO_DIR/scripts/desktop/configure-desktop/configure_desktop.py"
NETBIRD_HELPER="$REPO_DIR/scripts/network/netbird-setup/configure_netbird.py"
NETBIRD_ARGS=(--management-url "$NETBIRD_MANAGEMENT_URL")
if [[ -n "$NETBIRD_HOSTNAME" ]]; then NETBIRD_ARGS+=(--hostname "$NETBIRD_HOSTNAME"); fi
if [[ $CONFIGURE_NETBIRD -eq 1 ]]; then
  [[ -n "${SELECTED[vpn]+x}" ]] || die "--configure-netbird requires the vpn group"
  [[ -f "$NETBIRD_HELPER" ]] || die "Missing NetBird configuration helper"
fi
if [[ $CONFIGURE_DESKTOP -eq 1 ]]; then
  [[ -n "${SELECTED[ui]+x}" ]] || die "--configure-desktop requires the ui group"
  [[ -f "$DESKTOP_HELPER" ]] || die "Missing desktop configuration helper"
fi
if [[ $DEPLOY_KANATA -eq 1 ]]; then
  [[ -n "${SELECTED[keyboard]+x}" ]] || die "--deploy-kanata requires the keyboard group"
  [[ -f "$KANATA_HELPER" && -f "$REPO_DIR/.config/systemd/kanata.service" && -f "$REPO_DIR/.config/kanata/kanata.kbd" ]] || die "Missing Kanata deployment files"
fi
if [[ $CONFIGURE_LID -eq 1 ]]; then
  [[ -n "${SELECTED[hypr]+x}" ]] || die "--configure-lid requires the hypr group"
  [[ -f "$LID_HELPER" ]] || die "Missing lid configuration helper"
fi

command -v pacman >/dev/null 2>&1 || die "Run this script on an installed Arch Linux system"
if [[ $DRY_RUN -eq 0 && $CHECK_ONLY -eq 0 ]]; then
  if [[ "$AUR_HELPER" != none || $STOW -eq 1 || $DEPLOY_KANATA -eq 1 || $CONFIGURE_LID -eq 1 || $CONFIGURE_DESKTOP -eq 1 || $CONFIGURE_NETBIRD -eq 1 ]]; then
    [[ $EUID -ne 0 ]] || die "Run AUR, dotfile and hardware setup as your normal user, not root"
  fi
fi
# Lid hardware/config conflicts are checked before installing packages.
if [[ $CONFIGURE_LID -eq 1 && $CHECK_ONLY -eq 0 ]]; then bash "$LID_HELPER" --dry-run; fi

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
    vpn) packages=("${PKGS_VPN[@]}") ;;
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
    keyboard|comms) packages=() ;;
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
    --ignore '(^|/)hypr-lid\.service\.d(/|$)'
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
  if [[ -n "$CONFIG_SOURCE" ]]; then
    if ! copy_app_configs; then incomplete=1; fi
  fi
  if [[ $DEPLOY_KANATA -eq 1 ]]; then
    if ! bash "$KANATA_HELPER" --check; then incomplete=1; fi
  fi
  if [[ $CONFIGURE_LID -eq 1 ]]; then
    if ! bash "$LID_HELPER" --check; then incomplete=1; fi
  fi
  if [[ $CONFIGURE_DESKTOP -eq 1 ]]; then
    if ! python3 "$DESKTOP_HELPER" --check; then incomplete=1; fi
  fi
  if [[ $CONFIGURE_NETBIRD -eq 1 ]]; then
    if ! python3 "$NETBIRD_HELPER" --check "${NETBIRD_ARGS[@]}"; then incomplete=1; fi
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
if [[ $CONFIGURE_DESKTOP -eq 1 ]]; then run python3 "$DESKTOP_HELPER" --apply; fi
if [[ $DEPLOY_KANATA -eq 1 ]]; then
  if [[ $DRY_RUN -eq 0 ]] && ! pacman -Q kanata &>/dev/null; then
    echo 'Kanata deployment pending: install/review kanata first.'
    pending=1
  else
    run bash "$KANATA_HELPER" --activate
  fi
fi
if [[ $CONFIGURE_LID -eq 1 ]]; then run bash "$LID_HELPER" --apply; fi
if [[ $CONFIGURE_NETBIRD -eq 1 ]]; then
  if [[ $DRY_RUN -eq 0 ]] && ! pacman -Q netbird &>/dev/null; then
    echo 'NetBird configuration pending: install/review netbird first.'
    pending=1
  else
    run python3 "$NETBIRD_HELPER" --apply "${NETBIRD_ARGS[@]}"
  fi
fi
if [[ -n "$CONFIG_SOURCE" && $DRY_RUN -eq 0 ]]; then copy_app_configs; fi

if [[ $DRY_RUN -eq 0 && ( $DEPLOY_KANATA -eq 1 || $CONFIGURE_LID -eq 1 ) ]]; then
  echo "Hardware deployment was explicitly selected; no shell or disk layout changed."
elif [[ $DRY_RUN -eq 0 && $CONFIGURE_NETBIRD -eq 1 ]]; then
  echo "NetBird activation was explicitly selected; no shell or disk layout changed."
else
  echo "No services started; no shell or disk layout changed."
fi
if [[ -z "$CONFIG_SOURCE" ]]; then echo "No private application data copied."; fi
echo "Finish plugins, Python environments and host-specific settings using docs/migration.md."
if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry run only; nothing changed."
  exit 0
fi
if [[ $pending -eq 1 ]]; then
  echo "Setup incomplete: packages or an explicitly selected deployment remain pending."
  exit 1
fi
echo "Selected package setup completed."
