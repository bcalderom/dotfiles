#!/usr/bin/env python3
"""NetBird setup with fake systemd/status/SSO, never real services or identities."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import unittest
from unittest import mock


SOURCE = Path(__file__).resolve().parents[1] / "configure_netbird.py"
SPEC = importlib.util.spec_from_file_location("configure_netbird", SOURCE)
NETBIRD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NETBIRD)
MAIN = "netbird@main.service"
LEGACY = "netbird.service"


class NetBirdSetupTests(unittest.TestCase):
    def setUp(self):
        self.states = {
            MAIN: {"LoadState": "loaded", "ActiveState": "inactive", "UnitFileState": "disabled"},
            LEGACY: {"LoadState": "not-found", "ActiveState": "inactive", "UnitFileState": ""},
        }
        self.status = {"management": {"url": NETBIRD.DEFAULT_URL, "connected": False},
                       "fqdn": "", "netbirdIp": ""}
        self.commands = []
        self.fail_up = False
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(mock.patch.object(NETBIRD.shutil, "which", return_value="/mock/bin"))
        self.stack.enter_context(mock.patch.object(NETBIRD.os, "geteuid", return_value=1000))
        self.stack.enter_context(mock.patch.object(NETBIRD.sys.stdin, "isatty", return_value=True))
        self.stack.enter_context(mock.patch.object(NETBIRD.subprocess, "run", side_effect=self.command))
        self.output = io.StringIO()
        self.stack.enter_context(contextlib.redirect_stdout(self.output))

    def command(self, argv, **kwargs):
        self.commands.append(argv)
        output = ""
        if argv[:2] == ["systemctl", "show"]:
            output = "\n".join(key + "=" + value for key, value in self.states[argv[2]].items())
        elif argv[:2] == ["sudo", "systemctl"]:
            if argv[2] == "enable":
                self.states[argv[3]]["UnitFileState"] = "enabled"
            elif argv[2] == "start":
                self.states[argv[3]]["ActiveState"] = "active"
            else:
                self.fail("Unexpected service mutation: " + repr(argv))
        elif argv[0] == "netbird" and "status" in argv:
            output = json.dumps(self.status)
        elif argv[0] == "netbird" and "up" in argv:
            if self.fail_up:
                raise subprocess.CalledProcessError(1, argv, stderr="PRIVATE_FIXTURE auth code")
            self.status["management"]["connected"] = True
            self.status["netbirdIp"] = "100.64.0.2/16"
            hostname = argv[argv.index("--hostname") + 1] if "--hostname" in argv else "fixture"
            self.status["fqdn"] = hostname + ".example.test"
        else:
            self.fail("Unexpected command: " + repr(argv))
        return subprocess.CompletedProcess(argv, 0, output, "")

    def connected(self, unit=MAIN):
        self.states[unit].update(LoadState="loaded", ActiveState="active", UnitFileState="enabled")
        self.status.update(fqdn="fixture.example.test", netbirdIp="100.64.0.2/16")
        self.status["management"]["connected"] = True

    def assert_read_only(self):
        self.assertFalse(any(argv[0] == "sudo" or "up" in argv for argv in self.commands))

    def test_preview_does_not_run_any_commands(self):
        self.assertEqual(NETBIRD.configure("dry-run"), 0)
        self.assertFalse(self.commands)

    def test_check_is_read_only_and_detects_pending_or_ready(self):
        self.assertEqual(NETBIRD.configure("check"), 1)
        self.connected()
        self.assertEqual(NETBIRD.configure("check"), 0)
        self.assert_read_only()

    def test_apply_enables_starts_and_connects_fresh_peer(self):
        self.assertEqual(NETBIRD.configure("apply", hostname="fixture"), 0)
        self.assertIn(["sudo", "systemctl", "enable", MAIN], self.commands)
        self.assertIn(["sudo", "systemctl", "start", MAIN], self.commands)
        up = next(argv for argv in self.commands if "up" in argv)
        self.assertIn("unix:///var/run/netbird/main.sock", up)
        self.assertIn("--hostname", up)
        self.assertNotIn("--allow-server-ssh", up)
        self.assertNotIn("--setup-key", up)

    def test_connected_apply_never_restarts_or_reconnects(self):
        self.connected()
        self.assertEqual(NETBIRD.configure("apply"), 0)
        self.assert_read_only()

    def test_legacy_active_service_is_preserved(self):
        self.connected(LEGACY)
        self.assertEqual(NETBIRD.configure("apply"), 0)
        addresses = [argv[2] for argv in self.commands if argv[0] == "netbird"]
        self.assertEqual(set(addresses), {"unix:///var/run/netbird.sock"})
        self.assert_read_only()

    def test_multiple_active_services_are_refused_without_stopping(self):
        self.connected()
        self.connected(LEGACY)
        with self.assertRaisesRegex(ValueError, "Multiple"):
            NETBIRD.configure("apply")
        self.assert_read_only()

    def test_existing_peer_is_not_silently_moved_or_renamed(self):
        self.connected()
        for settings in ({"management_url": "https://other.example.test"}, {"hostname": "other"}):
            with self.subTest(settings=settings), self.assertRaises(ValueError):
                NETBIRD.configure("apply", **settings)
        self.status["management"]["connected"] = False
        with self.assertRaises(ValueError):
            NETBIRD.configure("apply", management_url="https://other.example.test")
        self.assert_read_only()

    def test_invalid_urls_or_hostnames_fail_before_commands(self):
        for url in ("http://example.test", "https://user:pass@example.test", "https://example.test?a=b",
                    "https://example.test/#token", "https://example.test:99999"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                NETBIRD.configure("dry-run", management_url=url)
        with self.assertRaises(ValueError):
            NETBIRD.configure("dry-run", hostname="invalid hostname")
        self.assertFalse(self.commands)

    def test_new_peer_requires_interactive_authentication(self):
        with mock.patch.object(NETBIRD.sys.stdin, "isatty", return_value=False):
            with self.assertRaisesRegex(ValueError, "interactive"):
                NETBIRD.configure("apply")
        self.assert_read_only()

    def test_missing_client_or_service_is_incomplete(self):
        self.states[MAIN]["LoadState"] = "not-found"
        self.assertEqual(NETBIRD.configure("check"), 1)
        self.assert_read_only()

    def test_unreadable_running_daemon_does_not_trigger_reregistration(self):
        self.connected()
        with mock.patch.object(NETBIRD, "client_status", return_value={}):
            with self.assertRaisesRegex(ValueError, "unknown peer"):
                NETBIRD.configure("apply")
        self.assert_read_only()

    def test_failure_does_not_echo_authentication_material(self):
        self.fail_up = True
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            self.assertEqual(NETBIRD.main(["--apply"]), 2)
        self.assertNotIn("PRIVATE_FIXTURE", self.output.getvalue() + errors.getvalue())


if __name__ == "__main__":
    unittest.main()
