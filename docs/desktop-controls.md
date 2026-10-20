# Desktop controls, calendar and Files

The desktop stays on Hyprland + Waybar. SwayNC provides a combined controls and
notification panel; GNOME Shell is not required.

## Packages

The bootstrapper's `ui` group installs Nautilus (GNOME Files), GVfs, gsimplecal,
XDG user-directory tools, the GTK portal and Python for the settings helper.
On an existing Arch installation, review and run the normal full-upgrade transaction:

```bash
sudo pacman -Syu --needed nautilus gvfs gsimplecal
```

Nothing removes Dolphin or its settings. Until Nautilus is installed, **Super + E**
still opens Dolphin. Directory associations prefer `org.gnome.Nautilus.desktop`
and retain Dolphin as a fallback via `.config/hyprland-mimeapps.list`. This
desktop-specific file leaves unrelated, host-local MIME associations untouched.
SMB shares and Android phones may additionally
need `gvfs-smb` and `gvfs-mtp`; install only the backends you use.

Files is simpler than Dolphin and does not provide its split-pane view. Changing
the default file manager does not replace application file-picker dialogs.

## Repeatable setup

Run as the desktop user, with an already reviewed AUR helper if required:

```bash
bash setup.sh --only ui --stow --configure-desktop --dry-run
bash setup.sh --only ui --aur yay --stow --configure-desktop
bash setup.sh --only ui --check --stow --configure-desktop
```

`--configure-desktop` is opt-in and requires the `ui` group. It prepares the
calendar locale, persists the dark preference, creates missing personal folders
and appends missing sidebar bookmarks. Existing custom paths, disabled folders,
bookmark labels/order and files are preserved. Stow still refuses conflicting
dotfiles; inspect those before deployment rather than adopting or overwriting.

For an existing linked checkout whose packages are already installed, the
[desktop settings helper](../scripts/desktop/configure-desktop/README.md) can be
previewed/applied/checked on its own, without a package transaction. It does not
close applications or restart services; reloads remain separate actions below.

## Interaction

- **Right-hand control pill:** network, volume, active power profile and
  notification status. Left-click any icon to toggle SwayNC.
- **Right-click network / volume:** open the existing connection editor / mixer.
- **Right-click the notification icon:** toggle Do Not Disturb.
- **Panel:** volume (including per-application controls), internal display
  brightness, power-saver/balanced profiles, network/audio settings, screen lock,
  the existing quick menu and notifications. The brightness slider controls the
  laptop backlight, not an external monitor. It uses SwayNC's default backlight
  device; other hardware may need `widget-config.backlight.device` adjusted.
- **Resources icon:** click to expand/collapse storage, temperature, CPU and RAM
  inside the bar. Battery and privacy indicators always remain outside the drawer.
- **Clock:** click to open/close gsimplecal, or press Escape while it is focused
  to close it. Moving the pointer or changing focus does not dismiss the calendar,
  so days and months remain interactive. Its Hyprland rule places it below the
  clock on the current monitor. Hovering does not show a second calendar: the
  clock's tooltip is disabled. Calendar config changes apply on its next launch.
- **Super + N / Super + Shift + N:** existing panel / Do Not Disturb shortcuts.
- **Super + E:** open Files, falling back to Dolphin when Files is unavailable.

The look follows the existing dark palette rather than copying Ubuntu's light
theme. The calendar is date-only, without event synchronization or notifications.
This is intentionally not a replica of GNOME's two independent dropdown panels.
SwayNC 0.12.6 has no calendar widget, so the clock uses a separate GTK calendar.
Its CSS is scoped to gsimplecal and does not restyle other GTK applications.

## Monday-first calendar

GTK chooses the first day of the week from the locale. The clock launches only
gsimplecal with `en_GB.utf8`, preserving its English labels but starting weeks on
Monday. This does not change the desktop's language or locale.

`--configure-desktop` prepares that locale once per user, without sudo. The manual
equivalent, if not using the helper, is:

```bash
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/gsimplecal/locales"
localedef --no-archive -i en_GB -f UTF-8 "${XDG_DATA_HOME:-$HOME/.local/share}/gsimplecal/locales/en_GB.utf8"
```

The generated locale is host-local data, not part of the repository. The clock's
launch command sets `LOCPATH` only for the calendar to find it. Close and reopen
the calendar after applying this change.

## Files sidebar

`.config/user-dirs.dirs` defines Documents, Music, Pictures, Videos and Downloads
under `$HOME`, so Nautilus and other applications recognize the personal folders
and their special icons. Existing folders and their contents are not moved.

Nautilus 51 reads its sidebar bookmarks from `~/.config/gtk-3.0/bookmarks`, even
though it uses GTK 4. This host-local file pins those five folders in the order
above on a fresh setup. It contains absolute file URIs and stays ignored by Git;
`--configure-desktop` generates the missing entries for the destination user while
preserving existing bookmarks and labels. Alternatively, open a folder and press
**Ctrl + D** to bookmark it. Reorder bookmarks by dragging them in the sidebar.

Home, Recent, Starred, Network and Trash are Nautilus's built-in entries, not
duplicate bookmarks. Recent requires recent-file history and GVfs support, both
already enabled on this host. Disks and removable volumes depend on the actual
hardware; the example screenshot's volumes are not created or mounted.

## Files dark mode

Nautilus follows the GNOME/Libadwaita system color preference.
`--configure-desktop` sets it for the current user; the manual equivalent is:

```bash
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
```

This persists in the user's settings database, not in Git, and also affects other
GNOME applications that follow the system preference. It does not require forcing
an unsupported GTK theme or restarting the desktop. To restore the default:

```bash
gsettings reset org.gnome.desktop.interface color-scheme
```

## Apply and check

On a new checkout, use the repository's normal Stow simulation/linking flow first.
On the current machine `~/.config` already links to the checkout, so the new files
are available without re-stowing. Hyprland normally reloads its Lua file itself.

SwayNC supports reloading without restarting its service:

```bash
swaync-client --reload-config
swaync-client --reload-css
```

Waybar's default `SIGUSR2` action reloads its configuration:

```bash
pkill -USR2 -u "$(id -u)" -x waybar
```

No Hyprland logout, service stop or reboot is needed. Once packages are installed,
check **Super + E**, opening a folder via `xdg-open`, clock open/close and calendar
placement on each monitor, the resource drawer and the panel's sliders/buttons.

Repository checks (no real application launches or package installation):

```bash
python3 -B scripts/tests/test-desktop-config.py
python3 -B scripts/desktop/configure-desktop/tests/test_configure_desktop.py
bash scripts/tests/test-setup.sh
luac -p .config/hypr/hyprland.lua
hyprctl configerrors
```
