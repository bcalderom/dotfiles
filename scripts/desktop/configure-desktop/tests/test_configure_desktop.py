#!/usr/bin/env python3
"""Host-local desktop deployment, with no real settings or locale commands."""

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


SOURCE = Path(__file__).resolve().parents[1] / "configure_desktop.py"
SPEC = importlib.util.spec_from_file_location("configure_desktop", SOURCE)
DESKTOP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DESKTOP)


class ConfigureDesktopTests(unittest.TestCase):
    def setUp(self):
        base = "/tmp/opencode" if Path("/tmp/opencode").is_dir() else None
        self.temporary = tempfile.TemporaryDirectory(prefix="desktop-setup-", dir=base)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.config = self.home / ".config"
        self.data = self.home / ".local/share"
        self.commands = []
        self.dark = False
        self.locale_valid = True
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(mock.patch.dict(os.environ, {
            "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.config),
            "XDG_DATA_HOME": str(self.data),
        }))
        self.stack.enter_context(mock.patch.object(DESKTOP.os, "geteuid", return_value=1000))
        self.stack.enter_context(mock.patch.object(DESKTOP.shutil, "which", return_value="/mock/bin"))
        self.stack.enter_context(mock.patch.object(DESKTOP.subprocess, "run", side_effect=self.command))
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))

    def command(self, argv, **kwargs):
        self.commands.append(argv)
        output = ""
        if argv[:2] == ["gsettings", "get"]:
            output = "'prefer-dark'\n" if self.dark else "'default'\n"
        elif argv[:2] == ["gsettings", "set"]:
            self.dark = True
        elif argv[0] == "localedef":
            directory = Path(argv[-1])
            directory.mkdir(parents=True, exist_ok=True)
            (directory / "LC_TIME").write_text("generated fixture")
        elif argv[0] == "locale":
            output = "first_weekday=2\n" if self.locale_valid else "first_weekday=1\n"
        else:
            self.fail(f"Unexpected command: {argv}")
        return subprocess.CompletedProcess(argv, 0, output, "")

    def test_preview_and_check_do_not_write(self):
        self.assertEqual(DESKTOP.configure("dry-run"), 0)
        self.assertEqual(DESKTOP.configure("check"), 1)
        self.assertFalse(self.config.exists())
        self.assertFalse(self.data.exists())
        self.assertTrue(all(command[:2] == ["gsettings", "get"] for command in self.commands))

    def test_apply_and_check_all_settings(self):
        self.assertEqual(DESKTOP.configure("apply"), 0)
        self.assertTrue(self.dark)
        expected = [self.home / name for name in DESKTOP.FOLDERS.values()]
        for folder in expected:
            self.assertTrue(folder.is_dir())
        bookmarks = self.config / "gtk-3.0/bookmarks"
        self.assertEqual(bookmarks.read_text().splitlines(), [path.as_uri() for path in expected])
        self.assertEqual(DESKTOP.configure("check"), 0)

    def test_repeated_apply_does_not_duplicate_or_rewrite(self):
        DESKTOP.configure("apply")
        paths = [self.config / "user-dirs.dirs", self.config / "gtk-3.0/bookmarks"]
        before = [(path.read_bytes(), path.stat().st_mtime_ns) for path in paths]
        self.commands.clear()
        DESKTOP.configure("apply")
        self.assertEqual(before, [(path.read_bytes(), path.stat().st_mtime_ns) for path in paths])
        self.assertFalse(any(command[0] == "localedef" or command[:2] == ["gsettings", "set"]
                             for command in self.commands))

    def test_preserve_custom_folders_labels_and_disabled_folders(self):
        self.config.mkdir()
        settings = self.config / "user-dirs.dirs"
        settings.write_text('XDG_DOCUMENTS_DIR="$HOME/My Documents"\nXDG_MUSIC_DIR="$HOME"\n')
        bookmarks = self.config / "gtk-3.0/bookmarks"
        bookmarks.parent.mkdir()
        custom = self.home / "My Documents"
        original = custom.as_uri() + " Work documents\nfile:///existing Custom label\n"
        bookmarks.write_text(original)
        DESKTOP.configure("apply")
        self.assertTrue(custom.is_dir())
        self.assertFalse((self.home / "Documents").exists())
        self.assertFalse((self.home / "Music").exists())
        self.assertTrue(bookmarks.read_text().startswith(original))
        self.assertEqual(bookmarks.read_text().count(custom.as_uri()), 1)
        self.assertIn('XDG_MUSIC_DIR="$HOME"', settings.read_text())

    def test_invalid_or_unavailable_custom_paths_fail_before_changes(self):
        self.config.mkdir()
        settings = self.config / "user-dirs.dirs"
        for value in ('"$HOME/$(touch unsafe)"', '"$HOME/../../unavailable"'):
            settings.write_text(f"XDG_DOCUMENTS_DIR={value}\n")
            with self.assertRaises(ValueError):
                DESKTOP.configure("apply")
        self.assertFalse(self.commands)
        self.assertFalse(self.data.exists())

    def test_keep_existing_stow_symlink(self):
        self.config.mkdir()
        source = self.home / "managed-user-dirs"
        source.write_text('XDG_DOCUMENTS_DIR="$HOME/Documents"\n')
        target = self.config / "user-dirs.dirs"
        target.symlink_to(source)
        DESKTOP.configure("apply")
        self.assertTrue(target.is_symlink())
        self.assertIn("XDG_DOWNLOAD_DIR", source.read_text())

    def test_invalid_locale_does_not_pass_check(self):
        DESKTOP.configure("apply")
        self.locale_valid = False
        self.assertEqual(DESKTOP.configure("check"), 1)

    def test_missing_command_or_root_refused(self):
        with mock.patch.object(DESKTOP.shutil, "which", return_value=None):
            with self.assertRaisesRegex(ValueError, "Missing command"):
                DESKTOP.configure("apply")
        with mock.patch.object(DESKTOP.os, "geteuid", return_value=0):
            with self.assertRaisesRegex(ValueError, "not root"):
                DESKTOP.configure("apply")
        self.assertFalse(self.config.exists())

    def test_concurrent_file_change_is_not_overwritten(self):
        path = self.home / "settings"
        path.write_text("user edit")
        with self.assertRaisesRegex(ValueError, "changed during setup"):
            DESKTOP.write_if_changed(path, "old", "new")
        self.assertEqual(path.read_text(), "user edit")


if __name__ == "__main__":
    unittest.main()
