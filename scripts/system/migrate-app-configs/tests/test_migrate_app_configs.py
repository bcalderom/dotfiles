#!/usr/bin/env python3
"""Synthetic config fixtures only; no real HOME, SSH, browser or credential access."""

from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "migrate_app_configs.py"
SPEC = importlib.util.spec_from_file_location("migrate_app_configs", SCRIPT)
migration = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(migration)


class ConfigMigrationTests(unittest.TestCase):
    def setUp(self):
        base = "/tmp/opencode" if Path("/tmp/opencode").is_dir() else None
        self.temp = tempfile.TemporaryDirectory(prefix="app-config-test-", dir=base)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.home = self.root / "target"
        self.source.mkdir(mode=0o700)
        self.home.mkdir(mode=0o700)
        self.settings = self.source / ".config/marktext"
        self.settings.mkdir(parents=True)
        (self.settings / "preferences.json").write_text('{"test_setting": "PRIVATE_FIXTURE"}\n')
        self.processes = patch.object(migration.subprocess, "check_output", return_value="")
        self.processes.start()
        self.addCleanup(self.processes.stop)
        self.output = io.StringIO()
        self.redirect = redirect_stdout(self.output)
        self.redirect.__enter__()
        self.addCleanup(self.redirect.__exit__, None, None, None)

    def request(self, **kwargs):
        source = migration.Source(str(self.source), ["marktext"])
        with patch.object(migration.sys.stdin, "isatty", return_value=True):
            return migration.migrate(source, ["marktext"], self.home, **kwargs)

    def test_named_apps_and_source_validation(self):
        self.assertEqual(migration.parse_apps("chromium,heidisql,chromium"), ["chromium", "heidisql"])
        self.assertEqual(migration.parse_apps("teams-for-linux,thunderbird,spotify,opencode"),
                         ["teams-for-linux", "thunderbird", "spotify", "opencode"])
        for value in ("", "all", "chromium,", "../.ssh", "chromium;id"):
            with self.subTest(value=value), self.assertRaises(migration.MigrationError):
                migration.parse_apps(value)
        for value in ("-bad@host", "boris@host;id", "user@host:/etc", "ssh://user@host"):
            with self.subTest(value=value), self.assertRaises(migration.MigrationError):
                migration.Source(value, ["marktext"])
        with self.assertRaises(migration.MigrationError):
            migration.Source(str(self.source), ["marktext"], "/socket")

    def test_dry_run_is_metadata_only_and_creates_nothing(self):
        before = sorted(self.root.rglob("*"))
        with patch.object(migration, "transfer") as transfer:
            self.assertIsNone(self.request(dry_run=True))
        transfer.assert_not_called()
        self.assertEqual(before, sorted(self.root.rglob("*")))
        self.assertNotIn("PRIVATE_FIXTURE", self.output.getvalue())

    def test_real_copy_requires_explicit_private_consent(self):
        with self.assertRaises(migration.MigrationError):
            self.request()
        self.assertFalse((self.home / ".local").exists())

    def test_root_cannot_copy(self):
        with patch.object(migration.os, "geteuid", return_value=0), self.assertRaises(migration.MigrationError):
            self.request(include_private=True)

    def test_closed_apps_required_on_source_and_destination(self):
        with patch.object(migration.subprocess, "check_output", return_value="marktext\n"), self.assertRaises(migration.MigrationError):
            self.request(dry_run=True)
        info = {"home": str(self.source), "host": "old-host", "roots": [{"app": "marktext", "path": ".config/marktext", "entries": 1}], "running": []}
        with patch.object(migration.Source, "inspect", return_value=info):
            with patch.object(migration.subprocess, "check_output", return_value="marktext\n"), self.assertRaises(migration.MigrationError):
                self.request(dry_run=True)

    def test_source_and_destination_cannot_be_same_home(self):
        with self.assertRaises(migration.MigrationError):
            migration.migrate(migration.Source(str(self.home), ["marktext"]), ["marktext"], self.home, dry_run=True)
        settings = self.home / ".config/marktext"
        settings.mkdir(parents=True)
        with self.assertRaises(migration.MigrationError):
            migration.migrate(migration.Source(str(self.home), ["marktext"]), ["marktext"], self.home, dry_run=True)

    def test_missing_or_symlinked_source_is_rejected(self):
        with self.assertRaises(ValueError):
            migration.Source(str(self.source), ["chromium"]).inspect()
        (self.settings / "outside").symlink_to(self.root)
        with self.assertRaises(ValueError):
            self.request(dry_run=True)

    def test_metadata_detects_removed_files_without_reading_contents(self):
        source = migration.Source(str(self.source), ["marktext"])
        before = source.inspect()["roots"][0]["metadata"]
        (self.settings / "preferences.json").unlink()
        after = source.inspect()["roots"][0]["metadata"]
        self.assertNotEqual(before, after)

    def test_special_files_are_rejected_without_reading_them(self):
        os.mkfifo(self.settings / "not-a-settings-file")
        with self.assertRaises(ValueError):
            self.request(dry_run=True)

    def test_destination_symlink_is_never_replaced(self):
        (self.home / ".config").symlink_to(self.source / ".config", target_is_directory=True)
        with self.assertRaises(migration.MigrationError):
            self.request(dry_run=True)
        self.assertTrue((self.home / ".config").is_symlink())

    def test_remote_probe_requires_verified_batch_ssh_and_checks_paths(self):
        info = {"home": "/home/boris", "host": "old-host", "roots": [{"app": "marktext", "path": ".config/marktext", "entries": 1}], "running": []}
        source = migration.Source("boris@old-host", ["marktext"], "/socket")
        with patch.object(migration.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=json.dumps(info))) as run:
            self.assertEqual(source.inspect(), info)
        command = run.call_args.args[0]
        self.assertIn("StrictHostKeyChecking=yes", command)
        self.assertIn("BatchMode=yes", command)
        self.assertIn("/socket", command)
        info["roots"][0]["path"] = ".ssh"
        with patch.object(migration.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=json.dumps(info))):
            with self.assertRaises(migration.MigrationError):
                source.inspect()

    def test_remote_probe_program_is_self_contained(self):
        source = migration.Source("boris@old-host", ["marktext"])
        program = "import json\n" + migration.inspect.getsource(migration.probe)
        namespace = {}
        exec(compile(program, "<probe-test>", "exec"), namespace)
        info = namespace["probe"](str(self.source), source.specs, migration.SKIP)
        self.assertEqual(info["roots"][0]["path"], ".config/marktext")

    def test_new_app_directories_are_found_without_reading_settings(self):
        for app, relative in (("teams-for-linux", ".config/teams-for-linux"),
                              ("thunderbird", ".thunderbird"), ("spotify", ".config/spotify")):
            with self.subTest(app=app):
                path = self.source / relative
                path.mkdir(parents=True)
                (path / "settings").write_text("PRIVATE_FIXTURE")
                roots = migration.Source(str(self.source), [app]).inspect()["roots"]
                self.assertEqual([root["path"] for root in roots], [relative])

    def test_new_apps_and_opencode_service_must_be_closed(self):
        for app, process in (("teams-for-linux", "teams-for-linux"), ("thunderbird", "thunderbird"),
                             ("spotify", "spotify"), ("opencode", "opencode"), ("opencode", "opencode-server")):
            with self.subTest(app=app, process=process):
                with patch.object(migration.subprocess, "check_output", return_value=process + "\n"):
                    with self.assertRaises(migration.MigrationError):
                        migration.check_destination(self.home, [app], [])

    def test_thunderbird_locks_are_skipped_but_other_symlinks_are_rejected(self):
        path = self.source / ".thunderbird"
        path.mkdir()
        (path / "lock").symlink_to("unused-transient-lock")
        (path / ".parentlock").touch()
        info = migration.Source(str(self.source), ["thunderbird"]).inspect()
        self.assertEqual(info["roots"][0]["entries"], 0)
        (path / "external-mail").symlink_to(self.root)
        with self.assertRaises(ValueError):
            migration.Source(str(self.source), ["thunderbird"]).inspect()

    def test_opencode_probe_selects_files_not_service_or_auth_state(self):
        path = self.source / ".config/opencode"
        path.mkdir(parents=True)
        for name in ("cli.json", "opencode.json", "service.json", "auth.json"):
            (path / name).write_text("PRIVATE_FIXTURE")
        source = migration.Source(str(self.source), ["opencode"])
        info = source.inspect()
        self.assertEqual({root["path"] for root in info["roots"]},
                         {".config/opencode/cli.json", ".config/opencode/opencode.json"})
        self.assertTrue(all(root["kind"] == "file" for root in info["roots"]))
        self.assertFalse(source.path(".config/opencode/cli.json").endswith("/"))
        self.assertNotIn("PRIVATE_FIXTURE", self.output.getvalue())
        program = "import json\n" + migration.inspect.getsource(migration.probe)
        namespace = {}
        exec(compile(program, "<probe-test>", "exec"), namespace)
        self.assertEqual(namespace["probe"](str(self.source), source.specs, migration.SKIP)["roots"], info["roots"])

    def test_opencode_files_reject_symlinks_and_wrong_types(self):
        path = self.source / ".config/opencode"
        path.mkdir(parents=True)
        cli = path / "cli.json"
        cli.symlink_to(self.settings / "preferences.json")
        with self.assertRaises(ValueError):
            migration.Source(str(self.source), ["opencode"]).inspect()
        cli.unlink()
        cli.mkdir()
        with self.assertRaises(ValueError):
            migration.Source(str(self.source), ["opencode"]).inspect()

    def test_opencode_legacy_definitions_are_discovered(self):
        for name in ("agent", "command", "skill"):
            path = self.source / ".config/opencode" / name
            path.mkdir(parents=True)
            (path / "example.md").write_text("synthetic legacy definition")
        roots = migration.Source(str(self.source), ["opencode"]).inspect()["roots"]
        self.assertEqual({root["path"] for root in roots},
                         {".config/opencode/agent", ".config/opencode/command", ".config/opencode/skill"})

    @unittest.skipIf(os.geteuid() == 0 or not shutil.which("rsync"), "requires rsync and normal user")
    def test_opencode_file_copy_preserves_unselected_state_and_backs_up_files(self):
        origin = self.source / ".config/opencode"
        target = self.home / ".config/opencode"
        origin.mkdir(parents=True)
        target.mkdir(parents=True)
        for name in ("cli.json", "opencode.jsonc", "config.local.json", "AGENTS.md"):
            (origin / name).write_text("PRIVATE_FIXTURE " + name)
        (origin / "service.json").write_text("source service must not migrate")
        (target / "cli.json").write_text("previous CLI settings")
        (target / "service.json").write_text("target service unchanged")
        (target / "auth.json").write_text("target auth unchanged")
        skills = origin / "skills/example"
        skills.mkdir(parents=True)
        (skills / "SKILL.md").write_text("synthetic skill")
        (skills / "node_modules").mkdir()
        (skills / "node_modules/cache").write_text("not portable")
        for name in ("agent", "command", "skill"):
            path = origin / name
            path.mkdir()
            (path / "example.md").write_text("synthetic legacy definition")
        source = migration.Source(str(self.source), ["opencode"])
        with patch.object(migration.sys.stdin, "isatty", return_value=True):
            batch = migration.migrate(source, ["opencode"], self.home, include_private=True,
                                      confirm=lambda _: "COPY opencode")
        self.assertEqual((target / "cli.json").read_text(), "PRIVATE_FIXTURE cli.json")
        self.assertEqual((batch / "backup/.config/opencode/cli.json").read_text(), "previous CLI settings")
        self.assertEqual((target / "service.json").read_text(), "target service unchanged")
        self.assertEqual((target / "auth.json").read_text(), "target auth unchanged")
        self.assertEqual((target / "skills/example/SKILL.md").read_text(), "synthetic skill")
        self.assertFalse((target / "skills/example/node_modules").exists())
        for name in ("agent", "command", "skill"):
            self.assertEqual((target / name / "example.md").read_text(), "synthetic legacy definition")
        self.assertNotIn("PRIVATE_FIXTURE", self.output.getvalue())

    @unittest.skipIf(os.geteuid() == 0 or not shutil.which("rsync"), "requires rsync and normal user")
    def test_thunderbird_copy_includes_mail_but_not_transient_locks(self):
        origin = self.source / ".thunderbird"
        (origin / "test.default/Mail/Local Folders").mkdir(parents=True)
        (origin / "profiles.ini").write_text("synthetic profile index")
        (origin / "test.default/Mail/Local Folders/Inbox").write_text("synthetic local mail")
        (origin / "test.default/lock").symlink_to("unused-lock")
        source = migration.Source(str(self.source), ["thunderbird"])
        with patch.object(migration.sys.stdin, "isatty", return_value=True):
            migration.migrate(source, ["thunderbird"], self.home, include_private=True,
                              confirm=lambda _: "COPY thunderbird")
        self.assertEqual((self.home / ".thunderbird/test.default/Mail/Local Folders/Inbox").read_text(), "synthetic local mail")
        self.assertFalse((self.home / ".thunderbird/test.default/lock").is_symlink())

    def test_failed_transfer_keeps_private_diagnostics_not_stdout(self):
        log = self.root / "diagnostics"
        log.mkdir(mode=0o700)
        source = migration.Source("boris@old-host", ["marktext"], "/socket")
        source.info = {"home": "/home/boris"}
        result = SimpleNamespace(returncode=23, stdout="", stderr="PRIVATE_FIXTURE\n")
        with patch.object(migration.subprocess, "run", return_value=result) as run:
            with self.assertRaises(migration.MigrationError):
                migration.transfer(source, ".config/marktext", self.home, log, verify=True)
        command = run.call_args.args[0]
        self.assertIn("--checksum", command)
        self.assertIn("--dry-run", command)
        self.assertIn("--no-owner", command)
        self.assertIn("--no-group", command)
        self.assertIn("--protect-args", command)
        self.assertNotIn("--delete", command)
        self.assertIn("StrictHostKeyChecking=yes", command[command.index("-e") + 1])
        self.assertNotIn("PRIVATE_FIXTURE", self.output.getvalue())

    @unittest.skipIf(os.geteuid() == 0, "real migration refuses root")
    def test_confirmation_and_private_home_required_before_copy(self):
        with self.assertRaises(migration.MigrationError):
            self.request(include_private=True, confirm=lambda _: "no")
        self.home.chmod(0o755)
        with self.assertRaises(migration.MigrationError):
            self.request(include_private=True, confirm=lambda _: "COPY marktext")
        self.assertFalse((self.home / ".local").exists())

    @unittest.skipIf(os.geteuid() == 0 or not shutil.which("rsync"), "requires rsync and normal user")
    def test_real_copy_verifies_backs_up_and_omits_cache_and_locks(self):
        target = self.home / ".config/marktext"
        target.mkdir(parents=True)
        (target / "preferences.json").write_text("previous fixture\n")
        cache = self.settings / "Cache"
        cache.mkdir()
        (cache / "discardable").write_text("cache\n")
        (self.settings / "SingletonLock").symlink_to("unused-lock")
        batch = self.request(include_private=True, confirm=lambda _: "COPY marktext")
        self.assertEqual((target / "preferences.json").read_text(), (self.settings / "preferences.json").read_text())
        self.assertEqual((batch / "backup/.config/marktext/preferences.json").read_text(), "previous fixture\n")
        self.assertFalse((target / "Cache").exists())
        self.assertFalse((target / "SingletonLock").is_symlink())
        self.assertEqual(stat.S_IMODE(batch.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((batch / "manifest.json").stat().st_mode), 0o600)
        self.assertNotIn("PRIVATE_FIXTURE", self.output.getvalue())

    @unittest.skipIf(os.geteuid() == 0, "real migration refuses root")
    def test_checksum_mismatch_keeps_existing_settings(self):
        target = self.home / ".config/marktext"
        target.mkdir(parents=True)
        (target / "preferences.json").write_text("previous fixture\n")
        with patch.object(migration, "transfer", side_effect=[None, migration.MigrationError("changed")]):
            with self.assertRaises(migration.MigrationError):
                self.request(include_private=True, confirm=lambda _: "COPY marktext")
        self.assertEqual((target / "preferences.json").read_text(), "previous fixture\n")

    @unittest.skipIf(os.geteuid() == 0 or not shutil.which("rsync"), "requires rsync and normal user")
    def test_source_deletion_during_copy_does_not_replace_destination(self):
        target = self.home / ".config/marktext"
        target.mkdir(parents=True)
        (target / "preferences.json").write_text("previous fixture\n")
        real_transfer = migration.transfer

        def changing_source(*args, **kwargs):
            real_transfer(*args, **kwargs)
            if not kwargs.get("verify"):
                (self.settings / "preferences.json").unlink()

        with patch.object(migration, "transfer", side_effect=changing_source):
            with self.assertRaises(migration.MigrationError):
                self.request(include_private=True, confirm=lambda _: "COPY marktext")
        self.assertEqual((target / "preferences.json").read_text(), "previous fixture\n")

    @unittest.skipIf(os.geteuid() == 0 or not shutil.which("rsync"), "requires rsync and normal user")
    def test_failed_promotion_restores_current_previous_settings(self):
        target = self.home / ".config/marktext"
        target.mkdir(parents=True)
        (target / "preferences.json").write_text("previous fixture\n")
        real_move = migration.move_no_replace

        def failing_move(source, destination):
            if "staged" in source.parts:
                raise OSError("simulated move failure")
            return real_move(source, destination)

        with patch.object(migration, "move_no_replace", side_effect=failing_move):
            with self.assertRaises(OSError):
                self.request(include_private=True, confirm=lambda _: "COPY marktext")
        self.assertEqual((target / "preferences.json").read_text(), "previous fixture\n")

    def test_no_clobber_move_preserves_racing_destination(self):
        origin = self.root / "move-source"
        target = self.root / "move-target"
        origin.mkdir()
        target.mkdir()
        with self.assertRaises(migration.MigrationError):
            migration.move_no_replace(origin, target)
        self.assertTrue(origin.is_dir())
        self.assertTrue(target.is_dir())


if __name__ == "__main__":
    unittest.main()
