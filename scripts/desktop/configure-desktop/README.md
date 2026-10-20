# Configure desktop preferences

Host-local settings for Files and the clock calendar. Normally invoked through
the root bootstrapper's explicit `--configure-desktop` option with the `ui` group.

```bash
python3 scripts/desktop/configure-desktop/configure_desktop.py --dry-run
python3 scripts/desktop/configure-desktop/configure_desktop.py --apply
python3 scripts/desktop/configure-desktop/configure_desktop.py --check
```

Run as the desktop user, never root. `--dry-run` (the default) and `--check` do
not write files, generate locales or change preferences. Apply is repeatable:

- Fill in missing XDG personal-folder definitions; preserve existing custom paths
  and intentionally disabled folders. Create missing folders inside HOME only.
- Append missing personal-folder bookmarks without removing/reordering existing
  entries or custom labels. Generate absolute URIs for this user, not in Git.
- Generate a private Monday-first `en_GB.utf8` locale with `localedef`; do not
  change `/etc/locale.gen`, the locale archive or the desktop's language.
- Persist GNOME/Libadwaita's `prefer-dark` setting through the user's D-Bus session.

Requires Python, GLib's `gsettings`, GNOME schemas and glibc locale tools/sources.
The `ui` group installs the required desktop packages. No disks are mounted, data
moved, applications closed or services restarted. Dotfile linking remains a
separate Stow action. Review hardware-specific backlight settings on each host.

Tests use temporary HOME/config/data directories and mocked preference/locale
commands, never the real desktop:

```bash
python3 -B scripts/desktop/configure-desktop/tests/test_configure_desktop.py
```
