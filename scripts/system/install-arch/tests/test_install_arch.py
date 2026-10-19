#!/usr/bin/env python3
"""Unit tests: no real disk, network, archinstall or privileged command is used."""

from contextlib import ExitStack, redirect_stderr, redirect_stdout
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "install_arch.py"
SPEC = importlib.util.spec_from_file_location("install_arch", SCRIPT)
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


def disk():
    return {
        "path": "/dev/nvme0n1", "type": "disk", "tran": "nvme", "rm": False,
        "ro": False, "size": 512_110_190_592, "log-sec": 512, "serial": "NEW-SSD-123",
        "wwn": "eui.123", "model": "Test SSD", "pttype": None, "mountpoints": [],
    }


class ProfileTests(unittest.TestCase):
    def test_geometry_and_current_schema(self):
        for sector in (512, 4096):
            device = disk() | {"log-sec": sector}
            config = installer.build_config(device)
            modification = config["disk_config"]["device_modifications"][0]
            self.assertTrue(modification["wipe"])
            self.assertEqual(config["version"], "4.5")
            parts = modification["partitions"]
            self.assertEqual([p["mountpoint"] for p in parts], ["/boot", "/", "/home"])
            self.assertEqual([p["fs_type"] for p in parts], ["fat32", "ext4", "ext4"])
            self.assertEqual(parts[0]["size"]["value"], 2048)
            self.assertEqual(parts[1]["size"]["value"], 102400)
            self.assertEqual(parts[0]["start"]["value"], 1)
            self.assertEqual(parts[0]["flags"], ["boot", "esp"])
            previous_end = 1
            for part in parts:
                self.assertNotIn("length", part)  # 4.5 uses size, not old docs' length.
                self.assertEqual(part["start"]["value"], previous_end)
                self.assertEqual(part["size"]["sector_size"]["value"], sector)
                self.assertEqual(part["size"]["unit"], "MiB")
                self.assertIsNone(part["dev_path"])
                previous_end += part["size"]["value"]
            self.assertLessEqual(previous_end * installer.MIB, device["size"] - installer.MIB)
            self.assertLess(device["size"] - previous_end * installer.MIB, 2 * installer.MIB)
            self.assertEqual(len({p["obj_id"] for p in parts}), 3)

    def test_identity_accounts_network_and_zram(self):
        config = installer.build_config(disk())
        self.assertEqual(config["hostname"], "arch-ryzen")
        self.assertEqual(config["timezone"], "America/Santiago")
        self.assertEqual(config["locale_config"], {"kb_layout": "us", "sys_lang": "en_US.UTF-8", "sys_enc": "UTF-8"})
        self.assertEqual(config["network_config"], {"type": "nm"})
        self.assertEqual(config["bootloader_config"]["bootloader"], "Systemd-boot")
        self.assertEqual(config["users"], [{"username": "boris", "enc_password": "!", "sudo": True, "groups": []}])
        self.assertEqual(config["root_enc_password"], "!")
        self.assertNotIn("disk_encryption", config["disk_config"])
        self.assertNotIn("!password", json.dumps(config))
        self.assertEqual(config["swap"], {"enabled": True, "algorithm": "zstd"})
        self.assertIn("min(ram / 2, 8192)", config["custom_commands"][0])
        self.assertNotIn("resume=", json.dumps(config))
        self.assertIn("amd-ucode", config["packages"])
        self.assertNotIn("intel-ucode", config["packages"])
        self.assertNotIn("sshd", config["services"])

    def test_refuse_unsafe_disks(self):
        for changes in (
            {"type": "part"}, {"tran": "usb"}, {"rm": True}, {"ro": True},
            {"size": 16 * installer.GIB}, {"size": 1_000_000_000_000},
            {"serial": "", "wwn": None}, {"serial": "bad\nserial"}, {"log-sec": 2048},
            {"mountpoints": ["/"]},
            {"children": [{"path": "/dev/nvme0n1p1", "type": "part", "mountpoints": ["[SWAP]"]}]},
            {"children": [{"path": "/dev/mapper/data", "type": "crypt", "mountpoints": []}]},
        ):
            with self.subTest(changes=changes), self.assertRaises(installer.InstallError):
                installer.validate_disk(disk() | changes)
        installer.validate_disk(disk())
        installer.validate_disk(disk() | {"serial": None})  # WWN fallback.

    def test_inventory_requires_tree_and_explicit_device(self):
        with patch.object(installer.subprocess, "run", return_value=SimpleNamespace(stdout='{"blockdevices": []}')) as run:
            self.assertEqual(installer.lsblk(Path("/dev/example")), [])
        self.assertIn("--tree", run.call_args.args[0])
        self.assertEqual(run.call_args.args[0][-1], "/dev/example")

    def test_reject_holders_and_non_block_paths(self):
        with ExitStack() as stack:
            stack.enter_context(patch.object(Path, "resolve", return_value=Path("/dev/nvme0n1")))
            stack.enter_context(patch.object(Path, "is_block_device", return_value=True))
            stack.enter_context(patch.object(installer, "lsblk", return_value=[disk()]))
            stack.enter_context(patch.object(Path, "is_dir", return_value=True))
            entries = stack.enter_context(patch.object(Path, "iterdir", return_value=iter([Path("holder")])))
            with self.assertRaises(installer.InstallError):
                installer.inspect_disk(Path("/dev/example"))
            entries.return_value = iter([])
            self.assertEqual(installer.inspect_disk(Path("/dev/example")), disk())
        with patch.object(Path, "resolve", return_value=Path("/dev/null")):
            with self.assertRaises(installer.InstallError):
                installer.inspect_disk(Path("/dev/null"))

    def test_example_and_json_never_access_disks_or_network(self):
        with patch.object(installer, "lsblk") as inventory, patch.object(installer, "inspect_disk") as inspect:
            with patch.object(installer, "urlopen") as network, redirect_stdout(io.StringIO()) as output:
                self.assertEqual(installer.main(["--example", "--json"]), 0)
            config = json.loads(output.getvalue())
            self.assertIn("SELECCIONAR", config["disk_config"]["device_modifications"][0]["device"])
        inventory.assert_not_called()
        inspect.assert_not_called()
        network.assert_not_called()

    def test_cli_rejects_implicit_target_and_unsafe_combinations(self):
        for arguments in ([], ["--example", "--install"], ["--disk", "/dev/x", "--json", "--install"], ["--list-disks", "--install"]):
            with self.subTest(arguments=arguments), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                installer.main(arguments)
            self.assertEqual(error.exception.code, 2)


class LiveEnvironmentTests(unittest.TestCase):
    def mounts(self, copytoram=False):
        mounts = [
            {"target": "/", "source": "airootfs", "fstype": "overlay",
             "options": "rw,lowerdir=/run/archiso/airootfs,upperdir=/run/archiso/cowspace/upperdir"},
            {"target": "/run/archiso/airootfs", "source": "/dev/loop0", "fstype": "squashfs", "options": "ro,relatime"},
        ]
        if copytoram:
            mounts.append({"target": "/run/archiso/copytoram", "source": "copytoram", "fstype": "tmpfs", "options": "rw"})
        else:
            mounts.append({"target": "/run/archiso/bootmnt", "source": "/dev/sda1", "fstype": "iso9660", "options": "ro"})
        return mounts

    def check(self, mounts, image_exists=True, backing="/run/archiso/copytoram/airootfs.sfs\n"):
        with ExitStack() as stack:
            stack.enter_context(patch.object(installer.subprocess, "run", return_value=SimpleNamespace(stdout=json.dumps({"filesystems": mounts}))))
            stack.enter_context(patch.object(Path, "is_file", return_value=image_exists))
            stack.enter_context(patch.object(Path, "read_text", return_value=backing))
            # A missing bootmnt is valid in copytoram; directory mount heuristics
            # must not replace checking the actual kernel mount table.
            stack.enter_context(patch.object(Path, "is_mount", return_value=False))
            return installer.check_live_environment()

    def test_regular_iso_is_accepted(self):
        self.assertEqual(self.check(self.mounts()), "bootmnt")

    def test_copytoram_without_bootmnt_is_accepted(self):
        self.assertEqual(self.check(self.mounts(copytoram=True)), "copytoram")

    def test_overlay_alone_or_installed_root_is_rejected(self):
        mounts = self.mounts()
        for snapshot in ([mounts[0]], mounts[1:], [mounts[0] | {"fstype": "ext4"}, *mounts[1:]]):
            with self.subTest(snapshot=snapshot), self.assertRaises(installer.InstallError):
                self.check(snapshot)

    def test_unrelated_overlay_lowerdir_is_rejected(self):
        mounts = self.mounts()
        mounts[0]["options"] = "rw,lowerdir=/run/archiso/airootfs-other"
        with self.assertRaises(installer.InstallError):
            self.check(mounts)

    def test_writable_or_non_squashfs_base_is_rejected(self):
        for changes in ({"options": "rw"}, {"fstype": "ext4"}):
            mounts = self.mounts()
            mounts[1].update(changes)
            with self.subTest(changes=changes), self.assertRaises(installer.InstallError):
                self.check(mounts)

    def test_copytoram_requires_tmpfs_image_and_loop_device(self):
        mounts = self.mounts(copytoram=True)
        for index, changes in ((2, {"fstype": "ext4"}), (1, {"source": "/dev/nvme0n1p3"})):
            snapshot = copy.deepcopy(mounts)
            snapshot[index].update(changes)
            with self.subTest(changes=changes), self.assertRaises(installer.InstallError):
                self.check(snapshot)
        with self.assertRaises(installer.InstallError):
            self.check(mounts, image_exists=False)

    def test_copytoram_requires_exact_loop_backing_file(self):
        with self.assertRaises(installer.InstallError):
            self.check(self.mounts(copytoram=True), backing="/home/airootfs.sfs\n")


class EnvironmentTests(unittest.TestCase):
    def test_normal_host_is_rejected_before_commands(self):
        with patch.object(installer.os, "geteuid", return_value=1000), patch.object(installer.subprocess, "run") as run:
            with self.assertRaises(installer.InstallError):
                installer.check_environment()
        run.assert_not_called()
        with patch.object(installer.os, "geteuid", return_value=0), patch.object(installer, "check_live_environment", side_effect=installer.InstallError("not live")):
            with self.assertRaises(installer.InstallError):
                installer.check_environment()

    def test_version_tty_and_internet_gates(self):
        with ExitStack() as stack:
            stack.enter_context(patch.object(installer.os, "geteuid", return_value=0))
            stack.enter_context(patch.object(installer, "check_live_environment", return_value="copytoram"))
            stack.enter_context(patch.object(Path, "is_mount", return_value=False))
            stack.enter_context(patch.object(Path, "is_dir", return_value=True))
            stack.enter_context(patch.object(Path, "is_symlink", return_value=False))
            stack.enter_context(patch.object(Path, "exists", return_value=False))
            stack.enter_context(patch.object(Path, "read_text", return_value="AuthenticAMD"))
            stack.enter_context(patch.object(installer.shutil, "which", return_value="/usr/bin/example"))
            version = stack.enter_context(patch.object(installer.importlib.metadata, "version", return_value="4.6"))
            network = stack.enter_context(patch.object(installer, "urlopen"))
            with self.assertRaises(installer.InstallError):
                installer.check_environment()
            network.assert_not_called()
            version.return_value = "4.5"
            tty = stack.enter_context(patch.object(installer.sys.stdin, "isatty", return_value=False))
            with self.assertRaises(installer.InstallError):
                installer.check_environment()
            network.assert_not_called()
            tty.return_value = True
            stack.enter_context(patch.object(installer.sys.stdout, "isatty", return_value=True))
            network.return_value.__enter__.return_value.status = 200
            installer.check_environment()
            network.assert_called_once_with("https://archlinux.org/", timeout=20)


class InstallationTests(unittest.TestCase):
    def setUp(self):
        temp_base = "/tmp/opencode" if Path("/tmp/opencode").is_dir() else None
        self.work = tempfile.TemporaryDirectory(prefix="install-arch-test-", dir=temp_base)
        self.addCleanup(self.work.cleanup)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(installer.tempfile, "TemporaryDirectory", return_value=self.work))
        self.stack.enter_context(redirect_stdout(io.StringIO()))
        self.confirm = self.stack.enter_context(patch("builtins.input", return_value="BORRAR NEW-SSD-123"))
        self.inspect = self.stack.enter_context(patch.object(installer, "inspect_disk", return_value=disk()))
        self.verify = self.stack.enter_context(patch.object(installer, "verify_installation"))
        self.target_empty = self.stack.enter_context(patch.object(installer, "check_target_empty"))
        self.calls = []
        self.call_options = []
        self.config = None
        self.run = self.stack.enter_context(patch.object(installer.subprocess, "run", side_effect=self.fake_run))

    def fake_run(self, command, **kwargs):
        self.calls.append(command)
        self.call_options.append(kwargs)
        if command[0] == "archinstall":
            config_path = Path(command[command.index("--config") + 1])
            self.config = json.loads(config_path.read_text())
            self.assertEqual(stat.S_IMODE(config_path.stat().st_mode), 0o600)
        return SimpleNamespace(stdout="boris P 2026-10-18 0 99999 7 -1\n")

    def invoke(self):
        installer.install(Path("/dev/nvme0n1"), disk(), installer.build_config(disk()))

    def test_cancel_never_partitions(self):
        self.confirm.return_value = "no"
        with self.assertRaises(installer.InstallError):
            self.invoke()
        self.assertEqual(len(self.calls), 1)
        self.assertIn("--dry-run", self.calls[0])
        self.inspect.assert_not_called()
        self.verify.assert_not_called()

    def test_changed_target_never_partitions(self):
        self.inspect.return_value = disk() | {"serial": "DIFFERENT"}
        with self.assertRaises(installer.InstallError):
            self.invoke()
        self.assertEqual(len(self.calls), 1)
        self.verify.assert_not_called()

    def test_parser_failure_prevents_confirmation(self):
        self.run.side_effect = subprocess.CalledProcessError(1, "archinstall --dry-run")
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke()
        self.confirm.assert_not_called()

    def test_new_mount_after_confirmation_prevents_partitioning(self):
        self.target_empty.side_effect = installer.InstallError("/mnt is now in use")
        with self.assertRaises(installer.InstallError):
            self.invoke()
        self.assertEqual(len(self.calls), 1)
        self.verify.assert_not_called()

    def test_success_sets_password_only_on_verified_target(self):
        self.invoke()
        self.assertIn("--dry-run", self.calls[0])
        self.assertNotIn("--dry-run", self.calls[1])
        self.verify.assert_called_once_with(disk())
        self.target_empty.assert_called_once()
        self.assertEqual(self.config["users"][0]["enc_password"], "!")
        self.assertEqual(self.calls[2], ["arch-chroot", "/mnt", "passwd", "boris"])
        self.assertEqual(self.calls[3], ["arch-chroot", "/mnt", "passwd", "-S", "boris"])
        self.assertFalse(any("reboot" in command for command in self.calls))

    def test_restrictive_parent_umask_does_not_reach_archinstall(self):
        previous = os.umask(0o077)
        try:
            self.invoke()
        finally:
            os.umask(previous)
        # fake_run also verifies that the config file remains mode 0600.
        self.assertEqual(self.call_options[0]["umask"], 0o022)
        self.assertEqual(self.call_options[1]["umask"], 0o022)

    def test_install_failure_does_not_set_password(self):
        def failing(command, **kwargs):
            if command[0] == "archinstall" and "--dry-run" not in command:
                raise subprocess.CalledProcessError(1, command)
            return self.fake_run(command, **kwargs)
        self.run.side_effect = failing
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke()
        self.verify.assert_not_called()
        self.assertFalse(any(command[0] == "arch-chroot" for command in self.calls))

    def test_unverified_installation_does_not_set_password(self):
        self.verify.side_effect = installer.InstallError("missing target")
        with self.assertRaises(installer.InstallError):
            self.invoke()
        self.assertEqual(len(self.calls), 2)

    def test_password_failure_reports_recovery(self):
        def failing(command, **kwargs):
            if command[:3] == ["arch-chroot", "/mnt", "passwd"]:
                raise subprocess.CalledProcessError(1, command)
            return self.fake_run(command, **kwargs)
        self.run.side_effect = failing
        with self.assertRaisesRegex(installer.InstallError, "NO reinicies"):
            self.invoke()


class TargetTests(unittest.TestCase):
    def test_verified_mounts_and_account(self):
        installed = disk() | {"pttype": "gpt", "children": []}
        for number, (mount, fs) in enumerate((("/mnt", "ext4"), ("/mnt/home", "ext4"), ("/mnt/boot", "vfat")), 1):
            installed["children"].append({"path": f"/dev/nvme0n1p{number}", "type": "part", "mountpoints": [mount], "fstype": fs})
        with patch.object(installer, "inspect_disk", return_value=installed):
            with patch.object(Path, "read_text", return_value="arch-ryzen\n"):
                outputs = ["1000\n", "1000\n", "boris wheel\n", "", "", "root L 2026-10-18\n", "C\nen_US.utf8\n", "", ""]
                with patch.object(installer, "verify_boot_files"), patch.object(installer.subprocess, "run", side_effect=[SimpleNamespace(stdout=text) for text in outputs]):
                    installer.verify_installation(disk())
        for change in ({"serial": "OTHER"}, {"pttype": "dos"}, {"children": []}):
            with patch.object(installer, "inspect_disk", return_value=installed | change):
                with self.assertRaises(installer.InstallError):
                    installer.verify_installation(disk())
        broken = copy.deepcopy(installed)
        broken["children"][0]["fstype"] = "btrfs"
        with patch.object(installer, "inspect_disk", return_value=broken), self.assertRaises(installer.InstallError):
            installer.verify_installation(disk())

    def test_missing_locale_or_unreadable_package_db_is_rejected(self):
        installed = disk() | {"pttype": "gpt", "children": []}
        for number, (mount, fs) in enumerate((("/mnt", "ext4"), ("/mnt/home", "ext4"), ("/mnt/boot", "vfat")), 1):
            installed["children"].append({"path": f"/dev/nvme0n1p{number}", "type": "part", "mountpoints": [mount], "fstype": fs})
        prefix = [SimpleNamespace(stdout=text) for text in ("1000\n", "1000\n", "boris wheel\n", "", "", "root L 2026-10-18\n")]
        cases = (
            ([SimpleNamespace(stdout="C\nPOSIX\n")], installer.InstallError),
            ([SimpleNamespace(stdout="en_US.utf8\n"), subprocess.CalledProcessError(255, "pacman -Qi git")], subprocess.CalledProcessError),
        )
        for suffix, error in cases:
            with self.subTest(error=error), patch.object(installer, "inspect_disk", return_value=installed):
                with patch.object(Path, "read_text", return_value="arch-ryzen\n"), patch.object(installer, "verify_boot_files"):
                    with patch.object(installer.subprocess, "run", side_effect=prefix + suffix), self.assertRaises(error):
                        installer.verify_installation(disk())

    def test_boot_files_fstab_and_zram(self):
        temp_base = "/tmp/opencode" if Path("/tmp/opencode").is_dir() else None
        with tempfile.TemporaryDirectory(prefix="install-boot-test-", dir=temp_base) as directory:
            target = Path(directory)
            files = {
                "boot/vmlinuz-linux": "kernel",
                "boot/initramfs-linux.img": "initramfs",
                "boot/EFI/systemd/systemd-bootx64.efi": "bootloader",
                "boot/loader/loader.conf": "default arch.conf\n",
                "boot/loader/entries/arch.conf": "linux /vmlinuz-linux\ninitrd /initramfs-linux.img\n",
                "etc/fstab": "UUID=a / ext4 defaults 0 1\nUUID=b /home ext4 defaults 0 2\nUUID=c /boot vfat defaults 0 2\n",
                "etc/systemd/zram-generator.conf": "[zram0]\nzram-size = min(ram / 2, 8192)\ncompression-algorithm = zstd\n",
            }
            for name, content in files.items():
                path = target / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            with patch.object(installer, "TARGET", target):
                installer.verify_boot_files()
                (target / "boot/loader/entries/arch.conf").write_text("invalid entry\n")
                with self.assertRaises(installer.InstallError):
                    installer.verify_boot_files()
                (target / "boot/loader/entries/arch.conf").write_text(files["boot/loader/entries/arch.conf"])
                (target / "etc/fstab").write_text("UUID=a / ext4 defaults 0 1\n")
                with self.assertRaises(installer.InstallError):
                    installer.verify_boot_files()


if __name__ == "__main__":
    unittest.main()
