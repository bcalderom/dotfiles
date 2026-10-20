#!/usr/bin/env python3
"""Prepare host-local Files/calendar settings without restarting applications."""

import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile


FOLDERS = {
    "DOCUMENTS": "Documents",
    "MUSIC": "Music",
    "PICTURES": "Pictures",
    "VIDEOS": "Videos",
    "DOWNLOAD": "Downloads",
}
SCHEMA = "org.gnome.desktop.interface"
LOCALE = "en_GB.utf8"


def directory_settings(path, home):
    original = path.read_text() if path.exists() else ""
    values = {}
    for line in original.splitlines():
        key, separator, value = line.partition("=")
        kind = key.strip().removeprefix("XDG_").removesuffix("_DIR")
        if separator and kind in FOLDERS:
            words = shlex.split(value, comments=True)
            if len(words) != 1:
                raise ValueError(f"Invalid personal directory: {key}")
            value = words[0].replace("${HOME}", str(home)).replace("$HOME", str(home))
            if "$" in value or not Path(value).is_absolute():
                raise ValueError(f"Unsupported personal directory: {key}")
            values[kind] = Path(os.path.normpath(value))
    additions = []
    for kind, name in FOLDERS.items():
        if kind not in values:
            values[kind] = home / name
            additions.append(f'XDG_{kind}_DIR="$HOME/{name}"')
    updated = original
    if additions:
        updated = original + ("\n" if original and not original.endswith("\n") else "")
        updated += "\n".join(additions) + "\n"
    # Pointing a special directory at HOME intentionally disables it.
    folders = list(dict.fromkeys(path for path in values.values() if path != home))
    for folder in folders:
        if folder.exists() and not folder.is_dir():
            raise ValueError(f"Personal folder is not a directory: {folder}")
        if not folder.exists() and not folder.resolve().is_relative_to(home.resolve()):
            raise ValueError(f"Custom folder outside HOME is unavailable: {folder}")
    return original, updated, folders


def bookmark_settings(path, folders):
    original = path.read_text() if path.exists() else ""
    known = {line.split()[0] for line in original.splitlines() if line.strip()}
    missing = [folder.as_uri() for folder in folders if folder.as_uri() not in known]
    updated = original
    if missing:
        updated += "\n" if original and not original.endswith("\n") else ""
        updated += "\n".join(missing) + "\n"
    return original, updated


def write_if_changed(path, original, updated):
    if original == updated:
        return
    # Preserve Stow symlinks rather than replacing the links themselves.
    target = path.resolve()
    if (target.read_text() if target.exists() else "") != original:
        raise ValueError(f"Configuration changed during setup: {path}")
    target.parent.mkdir(parents=True, exist_ok=True)
    mode = target.stat().st_mode & 0o777 if target.exists() else 0o644
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=target.parent, delete=False) as file:
            temporary = Path(file.name)
            file.write(updated)
        temporary.chmod(mode)
        temporary.replace(target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def user_environment():
    env = os.environ.copy()
    bus = Path(f"/run/user/{os.getuid()}/bus")
    if "DBUS_SESSION_BUS_ADDRESS" not in env and bus.is_socket():
        env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={bus}"
    return env


def calendar_locale_ready(locale_dir, env):
    if not (locale_dir / "LC_TIME").is_file() or not shutil.which("locale"):
        return False
    locale_env = {**env, "LC_ALL": LOCALE, "LOCPATH": str(locale_dir.parent)}
    result = subprocess.run(["locale", "-k", "LC_TIME"], env=locale_env,
                            text=True, capture_output=True)
    return (result.returncode == 0 and not result.stderr
            and "first_weekday=2" in result.stdout.splitlines())


def configure(mode):
    home = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    data = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
    if not config.is_absolute() or not data.is_absolute():
        raise ValueError("XDG config/data directories must be absolute paths")
    user_dirs = config / "user-dirs.dirs"
    original, updated, folders = directory_settings(user_dirs, home)
    bookmarks = config / "gtk-3.0/bookmarks"
    old_bookmarks, new_bookmarks = bookmark_settings(bookmarks, folders)
    locale_dir = data / "gsimplecal/locales" / LOCALE
    env = user_environment()
    locale_ready = calendar_locale_ready(locale_dir, env)
    dark = False
    if shutil.which("gsettings"):
        result = subprocess.run(["gsettings", "get", SCHEMA, "color-scheme"],
                                env=env, text=True, capture_output=True)
        dark = result.returncode == 0 and result.stdout.strip() == "'prefer-dark'"

    issues = []
    if original != updated:
        issues.append("personal directory definitions")
    issues.extend(f"folder {folder}" for folder in folders if not folder.is_dir())
    if old_bookmarks != new_bookmarks:
        issues.append("missing Files bookmarks (existing entries are preserved)")
    if not locale_ready:
        issues.append("Monday-first calendar locale")
    if not dark:
        issues.append("GNOME/Files dark preference")
    for issue in issues:
        print(f"Desktop setting pending: {issue}")
    if mode != "apply":
        if not issues:
            print("Desktop settings are configured.")
        return int(bool(issues)) if mode == "check" else 0

    if os.geteuid() == 0:
        raise ValueError("Run desktop configuration as the desktop user, not root")
    needed = ["gsettings", "locale"] + ([] if locale_ready else ["localedef"])
    for program in needed:
        if not shutil.which(program):
            raise ValueError(f"Missing command: {program}; install the setup ui group first")
    if not dark:
        subprocess.run(["gsettings", "set", SCHEMA, "color-scheme", "prefer-dark"],
                       env=env, check=True)
        value = subprocess.check_output(["gsettings", "get", SCHEMA, "color-scheme"],
                                        env=env, text=True).strip()
        if value != "'prefer-dark'":
            raise ValueError("Dark preference was not saved; check the user's D-Bus session")
    if not locale_ready:
        locale_dir.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["localedef", "--no-archive", "-i", "en_GB", "-f", "UTF-8",
                        str(locale_dir)], check=True)
    if not calendar_locale_ready(locale_dir, env):
        raise ValueError("The generated calendar locale is not valid and Monday-first")
    for folder in folders:
        folder.mkdir(parents=True, exist_ok=True)
    write_if_changed(user_dirs, original, updated)
    write_if_changed(bookmarks, old_bookmarks, new_bookmarks)
    print("Desktop settings applied; no files moved, apps stopped or services restarted.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    for mode in ("dry-run", "check", "apply"):
        modes.add_argument(f"--{mode}", dest="mode", action="store_const", const=mode)
    args = parser.parse_args()
    try:
        return configure(args.mode or "dry-run")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Desktop setup: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
