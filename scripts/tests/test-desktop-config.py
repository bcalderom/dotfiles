#!/usr/bin/env python3
"""Desktop wiring and launch fallbacks; never launch real desktop applications."""

import configparser
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / ".config"


class DesktopConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # This config uses whole-line comments, not inline JSONC comments.
        text = (CONFIG / "waybar/config.jsonc").read_text()
        cls.bar = json.loads(re.sub(r"^\s*//.*$", "", text, flags=re.MULTILINE))
        cls.panel = json.loads((CONFIG / "swaync/config.json").read_text())
        cls.hypr = (CONFIG / "hypr/hyprland.lua").read_text()

    def test_all_modules_are_configured(self):
        for position in ("left", "center", "right"):
            for module in self.bar[f"modules-{position}"]:
                self.assertIn(module, self.bar)
        for name, config in self.bar.items():
            if name.startswith("group/"):
                for module in config["modules"]:
                    self.assertIn(module, self.bar)

    def test_compact_controls_preserve_important_indicators(self):
        self.assertEqual(
            self.bar["modules-right"],
            ["group/system-stats", "privacy", "battery", "group/controls"],
        )
        for module in self.bar["group/controls"]["modules"]:
            self.assertEqual(self.bar[module]["on-click"], "swaync-client -t -sw")
        self.assertEqual(self.bar["network"]["on-click-right"], "nm-connection-editor")
        self.assertEqual(self.bar["pulseaudio"]["on-click-right"], "pavucontrol")
        self.assertTrue(self.bar["group/system-stats"]["drawer"]["click-to-reveal"])
        self.assertEqual(self.bar["battery"]["states"]["critical"], 15)

    def test_panel_has_controls_and_notifications(self):
        for widget in ("volume", "backlight", "buttons-grid", "dnd", "notifications"):
            self.assertIn(widget, self.panel["widgets"])
            self.assertIn(widget, self.panel["widget-config"])
        self.assertNotIn("calendar", self.panel["widgets"])
        actions = self.panel["widget-config"]["buttons-grid"]["actions"]
        for action in actions:
            subprocess.run(["/bin/sh", "-n", "-c", action["command"]], check=True)

    @unittest.skipUnless(Path("/etc/xdg/swaync/configSchema.json").is_file(),
                         "SwayNC schema is not installed")
    def test_widgets_use_installed_schema_fields(self):
        # Check local version compatibility without adding a JSON Schema dependency.
        schema = json.loads(Path("/etc/xdg/swaync/configSchema.json").read_text())
        for key in self.panel:
            if key != "$schema":
                self.assertIn(key, schema["properties"])
        types = {"string": str, "boolean": bool, "integer": int,
                 "number": (int, float), "array": list, "object": dict}
        for name, config in self.panel["widget-config"].items():
            self.assertIn(name, schema["widgets"])
            fields = schema["widgets"][name]["properties"]
            for key, value in config.items():
                self.assertIn(key, fields, f"{name}.{key}")
                self.assertIsInstance(value, types[fields[key]["type"]])

    def test_calendar_popup_configuration(self):
        self.assertFalse(self.bar["clock"]["tooltip"])
        self.assertNotIn("tooltip-format", self.bar["clock"])
        self.assertIn("LC_ALL=en_GB.utf8", self.bar["clock"]["on-click"])
        self.assertIn("/gsimplecal/locales", self.bar["clock"]["on-click"])
        calendar = dict(
            line.split(" = ", 1)
            for line in (CONFIG / "gsimplecal/config").read_text().splitlines()
            if line and not line.startswith("#")
        )
        self.assertEqual(calendar["close_on_unfocus"], "0")
        self.assertEqual(calendar["close_on_mouseleave"], "0")
        self.assertEqual(calendar["mainwindow_position"], "none")
        self.assertIn('match = { class = "[Gg]simplecal" }', self.hypr)
        self.assertIn('move = { "(monitor_w-window_w)/2", "48" }', self.hypr)

    def test_files_is_preferred_with_dolphin_as_fallback(self):
        mime = configparser.ConfigParser(interpolation=None)
        mime.read(CONFIG / "hyprland-mimeapps.list")
        self.assertEqual(
            mime["Default Applications"]["inode/directory"].split(";")[:2],
            ["org.gnome.Nautilus.desktop", "org.kde.dolphin.desktop"],
        )

    def test_personal_directories_use_portable_home_paths(self):
        directories = {}
        for line in (CONFIG / "user-dirs.dirs").read_text().splitlines():
            if line and not line.startswith("#"):
                key, value = line.split("=", 1)
                directories[key] = shlex.split(value)[0]
        self.assertEqual(directories, {
            "XDG_DOCUMENTS_DIR": "$HOME/Documents",
            "XDG_MUSIC_DIR": "$HOME/Music",
            "XDG_PICTURES_DIR": "$HOME/Pictures",
            "XDG_VIDEOS_DIR": "$HOME/Videos",
            "XDG_DOWNLOAD_DIR": "$HOME/Downloads",
        })

    def launch_with_mocks(self, command, available):
        base = "/tmp/opencode" if Path("/tmp/opencode").is_dir() else None
        with tempfile.TemporaryDirectory(prefix="desktop-test-", dir=base) as directory:
            work = Path(directory)
            for name in available:
                executable = work / name
                executable.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> "$MOCK_LOG"\n')
                executable.chmod(0o755)
            argv = shlex.split(command)
            argv[0] = shutil.which(argv[0])
            env = {**os.environ, "PATH": str(work), "MOCK_LOG": str(work / "log")}
            subprocess.run(argv, env=env, check=True, capture_output=True, timeout=5)
            return [Path(line).name for line in (work / "log").read_text().splitlines()]

    def test_clock_opens_calendar_or_explains_missing_package(self):
        command = self.bar["clock"]["on-click"]
        self.assertEqual(self.launch_with_mocks(command, ["gsimplecal", "notify-send"]),
                         ["gsimplecal"])
        self.assertEqual(self.launch_with_mocks(command, ["notify-send"]), ["notify-send"])

    def test_super_e_prefers_files_without_breaking_existing_install(self):
        command = re.search(r"local fileManager = \[\[(.*?)\]\]", self.hypr).group(1)
        self.assertEqual(self.launch_with_mocks(command, ["nautilus", "dolphin"]), ["nautilus"])
        self.assertEqual(self.launch_with_mocks(command, ["dolphin"]), ["dolphin"])


if __name__ == "__main__":
    unittest.main()
