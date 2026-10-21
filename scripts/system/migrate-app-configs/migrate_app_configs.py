#!/usr/bin/env python3
"""Opt-in migration of named application settings; never reads settings into logs."""

import argparse
import copy
import inspect
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import socket
import stat
import subprocess
import sys
import tempfile


APPS = {
    "ssh": {"paths": [".ssh/config", ".ssh/known_hosts"],
            "files": [".ssh/config", ".ssh/known_hosts"], "processes": []},
    "onlyoffice": {"paths": [".config/onlyoffice", ".local/share/onlyoffice"], "processes": ["DesktopEditors", "desktopeditors", "onlyoffice"]},
    "marktext": {"paths": [".config/marktext"], "processes": ["marktext"]},
    "heidisql": {"paths": [".config/heidisql"], "processes": ["heidisql", "heidisql-qt6"]},
    "chromium": {"paths": [".config/chromium"], "processes": ["chromium", "chromium-browser"]},
    "brave": {"paths": [".config/BraveSoftware/Brave-Browser"], "processes": ["brave", "brave-browser"]},
    "teams-for-linux": {"paths": [".config/teams-for-linux"], "processes": ["teams-for-linux"]},
    "thunderbird": {"paths": [".thunderbird", ".config/thunderbird"], "processes": ["thunderbird", "thunderbird-bin"],
                    "skip": ["lock", ".parentlock", "parent.lock", "cache2", "startupCache"]},
    "spotify": {"paths": [".config/spotify"], "processes": ["spotify"]},
    "opencode": {
        "paths": [".config/opencode/cli.json", ".config/opencode/opencode.json", ".config/opencode/opencode.jsonc",
                  ".config/opencode/config.local.json", ".config/opencode/config.local.jsonc", ".config/opencode/AGENTS.md",
                  ".config/opencode/agents", ".config/opencode/commands", ".config/opencode/skills",
                  ".config/opencode/agent", ".config/opencode/command", ".config/opencode/skill",
                  ".config/opencode/plugins", ".config/opencode/themes"],
        "files": [".config/opencode/cli.json", ".config/opencode/opencode.json", ".config/opencode/opencode.jsonc",
                  ".config/opencode/config.local.json", ".config/opencode/config.local.jsonc", ".config/opencode/AGENTS.md"],
        "processes": ["opencode", "opencode-cli", "opencode-server"],
        "skip": ["node_modules", ".git", "__pycache__"],
    },
}
SKIP = ("Cache", "Code Cache", "GPUCache", "DawnCache", "ShaderCache", "GrShaderCache", "Crashpad",
        "SingletonLock", "SingletonCookie", "SingletonSocket", "DevToolsActivePort")


class MigrationError(Exception):
    """A failed precondition, transfer or verification; keep backups and staging."""


def probe(home, specs, skip):
    """Metadata-only probe, also sent over verified SSH to the source host."""
    import hashlib
    import os
    from pathlib import Path
    import socket
    import stat
    import subprocess

    home = Path(home).expanduser().absolute() if home else Path.home()
    if home.resolve() != home or not home.is_dir() or os.geteuid() == 0:
        raise ValueError("Use a normal user's real HOME or snapshot directory")
    names = subprocess.check_output(["ps", "-u", str(os.getuid()), "-o", "comm="], text=True).splitlines()
    names = {name.strip().lower()[:15] for name in names}
    running = [app for app, spec in specs.items() if any(name.lower()[:15] in names for name in spec["processes"])]
    roots = []
    for app, spec in specs.items():
        present = False
        excluded = set(skip) | set(spec.get("skip", []))
        for relative in spec["paths"]:
            root = home / relative
            if root.is_symlink() or root.resolve() != root:
                raise ValueError("Symlink in an application config root: " + relative)
            if not root.exists():
                continue
            is_file = relative in spec.get("files", [])
            if not (root.is_file() if is_file else root.is_dir()):
                raise ValueError("Unexpected config root type: " + relative)
            if root.stat().st_uid != os.getuid() or not os.access(root, os.R_OK if is_file else os.R_OK | os.X_OK):
                raise ValueError("Config root is inaccessible or foreign-owned: " + relative)
            count = 0
            metadata = hashlib.sha256()
            root_info = root.stat()
            if relative in spec.get("private_keys", []) and stat.S_IMODE(root_info.st_mode) & 0o077:
                raise ValueError("SSH identity must not be accessible to other users: " + relative)
            metadata.update(str((root_info.st_mode, root_info.st_size, root_info.st_mtime_ns)).encode())

            def walk_error(error):
                raise error

            tree = () if is_file else os.walk(root, followlinks=False, onerror=walk_error)
            for parent, dirs, files in tree:
                dirs[:] = sorted(name for name in dirs if name not in excluded)
                for name in sorted(dirs + [name for name in files if name not in excluded]):
                    path = Path(parent) / name
                    info = path.lstat()
                    if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
                        raise ValueError("Config tree contains a symlink or special file: " + relative)
                    if info.st_uid != os.getuid() or not os.access(path, os.R_OK):
                        raise ValueError("Config tree contains inaccessible or foreign-owned files: " + relative)
                    record = str(path.relative_to(root)) + "\0" + str((info.st_mode, info.st_size, info.st_mtime_ns))
                    metadata.update(record.encode() + b"\0")
                    count += 1
            roots.append({"app": app, "path": relative, "kind": "file" if is_file else "directory",
                          "entries": count, "metadata": metadata.hexdigest()})
            present = True
        if not present:
            raise ValueError("No supported config directory found for " + app)
    return {"home": str(home), "host": socket.gethostname(), "roots": roots, "running": running}


def parse_apps(value):
    apps = value.split(",")
    if not apps or any(app not in APPS for app in apps):
        raise MigrationError("Select named apps from: " + ",".join(APPS))
    return list(dict.fromkeys(apps))


class Source:
    def __init__(self, value, apps, control_path=None, ssh_keys=None):
        self.specs = {app: copy.deepcopy(APPS[app]) for app in apps}
        self.ssh_keys = list(dict.fromkeys(ssh_keys or []))
        if self.ssh_keys and "ssh" not in apps:
            raise MigrationError("--ssh-key requires selecting the ssh app")
        for name in self.ssh_keys:
            if (not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name)
                    or name in {"config", "known_hosts", "known_hosts.old", "authorized_keys"}
                    or name.endswith((".pub", "-cert.pub"))):
                raise MigrationError("Select an explicit SSH private-key basename, not a path or wildcard")
            relative = ".ssh/" + name
            self.specs["ssh"]["paths"].extend([relative, relative + ".pub"])
            self.specs["ssh"]["files"].extend([relative, relative + ".pub"])
        if "ssh" in apps:
            self.specs["ssh"]["private_keys"] = [".ssh/" + name for name in self.ssh_keys]
        self.remote = bool(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*@[A-Za-z0-9][A-Za-z0-9_.-]*", value))
        if not self.remote and ("@" in value or ":" in value):
            raise MigrationError("Use a local snapshot HOME or USER@HOST (SSH alias for custom ports/IPv6)")
        if control_path and not self.remote:
            raise MigrationError("An SSH control path requires a remote source")
        self.value = value if self.remote else str(Path(value).expanduser().absolute())
        self.ssh = ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes"]
        if control_path:
            self.ssh += ["-S", control_path]
        self.info = None

    def inspect(self):
        if self.remote:
            program = "import json\n" + inspect.getsource(probe)
            program += "\nprint(json.dumps(probe(None, " + repr(self.specs) + ", " + repr(SKIP) + ")))"
            result = subprocess.run(self.ssh + [self.value, shlex.join(["python3", "-c", program])], text=True, capture_output=True)
            if result.returncode:
                raise MigrationError("SSH source probe failed (exit " + str(result.returncode) + "); check authentication, host key, app state and config paths")
            try:
                info = json.loads(result.stdout)
            except ValueError as error:
                raise MigrationError("Invalid source metadata; no settings copied") from error
        else:
            info = probe(self.value, self.specs, SKIP)
        expected = {path for spec in self.specs.values() for path in spec["paths"]}
        if not isinstance(info, dict) or not isinstance(info.get("home"), str) or not Path(info["home"]).is_absolute():
            raise MigrationError("Invalid source HOME")
        if any(char in info["home"] for char in "\n\r\0"):
            raise MigrationError("Invalid source HOME")
        roots = info.get("roots", [])
        if not isinstance(roots, list) or not roots or any(not isinstance(root, dict) or not isinstance(root.get("path"), str) for root in roots):
            raise MigrationError("Invalid source config roots")
        if len({root["path"] for root in roots}) != len(roots):
            raise MigrationError("Invalid source config roots")
        for root in roots:
            if root.get("app") not in self.specs or root.get("path") not in self.specs[root["app"]]["paths"] or root["path"] not in expected:
                raise MigrationError("Source returned a path outside the selected applications")
            kind = "file" if root["path"] in self.specs[root["app"]].get("files", []) else "directory"
            if root.get("kind", "directory") != kind:
                raise MigrationError("Unexpected source config root type")
        for name in self.ssh_keys:
            if ".ssh/" + name not in {root["path"] for root in roots}:
                raise MigrationError("Selected SSH identity not found: " + name)
        if info.get("running"):
            raise MigrationError("Close selected apps on source first: " + ", ".join(info["running"]))
        self.info = info
        return info

    def path(self, relative):
        spec = next(spec for spec in self.specs.values() if relative in spec["paths"])
        path = str(Path(self.info["home"]) / relative)
        if relative not in spec.get("files", []):
            path += "/"
        return self.value + ":" + path if self.remote else path


def safe_path(home, relative, kind="directory"):
    path = home / relative
    if path.is_symlink() or path.resolve() != path:
        raise MigrationError("Destination path is a symlink: " + relative)
    if path.exists() and not (path.is_file() if kind == "file" else path.is_dir()):
        raise MigrationError("Unexpected destination config root type: " + relative)
    return path


def check_destination(home, apps, roots, ssh_keys=()):
    if home.resolve() != home or not home.is_dir() or home.stat().st_uid != os.getuid():
        raise MigrationError("Destination must be your real HOME")
    names = subprocess.check_output(["ps", "-u", str(os.getuid()), "-o", "comm="], text=True).splitlines()
    names = {name.strip().lower()[:15] for name in names}
    busy = [app for app in apps if any(name.lower()[:15] in names for name in APPS[app]["processes"])]
    if busy:
        raise MigrationError("Close selected apps on destination first: " + ", ".join(busy))
    if "ssh" in apps:
        directory = safe_path(home, ".ssh")
        if directory.exists() and directory.stat().st_uid != os.getuid():
            raise MigrationError("SSH directory belongs to another user")
        selected = {root["path"] for root in roots}
        for name in ssh_keys:
            public = ".ssh/" + name + ".pub"
            if public not in selected and (home / public).exists():
                raise MigrationError("Existing SSH public companion has no source counterpart; review " + public)
    for root in roots:
        path = safe_path(home, root["path"], root.get("kind", "directory"))
        if path.exists() and path.stat().st_uid != os.getuid():
            raise MigrationError("Destination config belongs to another user: " + root["path"])


def transfer(source, relative, destination, log_dir, verify=False):
    command = ["rsync", "-aHAX", "--no-owner", "--no-group", "--no-devices", "--no-specials", "--protect-args"]
    spec = next(spec for spec in source.specs.values() if relative in spec["paths"])
    for name in (*SKIP, *spec.get("skip", [])):
        command += ["--exclude=" + name]
    if source.remote:
        command += ["-e", shlex.join(source.ssh)]
    if verify:
        command += ["--checksum", "--dry-run", "--itemize-changes", "--out-format=%i"]
    suffix = "" if relative in spec.get("files", []) else "/"
    command += ["--", source.path(relative), str(destination) + suffix]
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode or result.stderr:
        with (log_dir / "rsync-errors.log").open("a") as handle:
            handle.write(result.stderr)
        raise MigrationError("rsync failed (exit " + str(result.returncode) + "); private diagnostics in " + str(log_dir))
    if verify and result.stdout.strip():
        raise MigrationError("Source changed or checksum/metadata differ; staging retained in " + str(log_dir))


def move_no_replace(source, target):
    if source.stat().st_dev != target.parent.stat().st_dev:
        raise MigrationError("Config and backup must be on the same filesystem")
    original = (source.stat().st_dev, source.stat().st_ino)
    subprocess.run(["mv", "--no-clobber", "--no-target-directory", "--", str(source), str(target)], check=True, capture_output=True)
    if source.exists() or source.is_symlink() or (target.stat().st_dev, target.stat().st_ino) != original:
        raise MigrationError("Destination appeared during migration; not overwritten: " + str(target))


def migrate(source, apps, home, dry_run=False, include_private=False, confirm=None):
    if not dry_run and (os.geteuid() == 0 or not include_private):
        raise MigrationError("Real copying requires a normal user and --include-private-configs")
    if not source.remote and Path(source.value) == home:
        raise MigrationError("Source and destination are the same HOME")
    info = source.inspect()
    roots = info["roots"]

    def check_source():
        refreshed = source.inspect()
        before = {(root["app"], root["path"], root.get("metadata")) for root in roots}
        after = {(root["app"], root["path"], root.get("metadata")) for root in refreshed["roots"]}
        if before != after or (info["host"], info["home"]) != (refreshed["host"], refreshed["home"]):
            raise MigrationError("Source config changed; keep apps closed and review retained staging")

    if info["host"] == socket.gethostname() and Path(info["home"]) == home:
        raise MigrationError("Source and destination are the same HOME")
    check_destination(home, apps, roots, source.ssh_keys)
    for root in roots:
        action = "back up and replace" if (home / root["path"]).exists() else "create"
        print(root["app"] + ": " + action + " " + root["path"])
    if any(app in apps for app in ("chromium", "brave")):
        print("Browser passwords/sessions may need the original keyring or reauthentication; no keyrings are copied.")
    if "teams-for-linux" in apps or "spotify" in apps:
        print("Teams/Spotify may need reauthentication; system keyrings and media caches are not copied.")
    if "thunderbird" in apps:
        print("Thunderbird includes local mail and saved logins inside its profile; external mail stores are not copied.")
    if "opencode" in apps:
        print("OpenCode v2: global settings/definitions only; no session database, provider auth, service registration or logs.")
        print("Close OpenCode clients and its background service on both hosts before copying; no service is stopped automatically.")
    if "ssh" in apps:
        print("SSH: config/known_hosts and explicitly named identities only; no authorized_keys, agent sockets or other keys.")
        if source.ssh_keys:
            print("Private identities selected: " + ", ".join(source.ssh_keys))
    if dry_run:
        print("Read-only preview: no config contents read or copied, no apps stopped.")
        return None
    if stat.S_IMODE(home.stat().st_mode) != 0o700:
        raise MigrationError("Make destination HOME private (mode 700) before copying private settings")
    if not sys.stdin.isatty():
        raise MigrationError("Real config migration needs an interactive terminal")
    phrase = "COPY " + ",".join(apps)
    if source.ssh_keys:
        phrase += " KEYS " + ",".join(source.ssh_keys)
    if (confirm or input)("May copy saved credentials. Type exactly " + phrase + ": ").strip() != phrase:
        raise MigrationError("Cancelled; no config contents copied")
    if not shutil.which("rsync"):
        raise MigrationError("Install rsync on both hosts first")
    state = safe_path(home, ".local/state/dotfiles-app-configs")
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    if state.stat().st_uid != os.getuid() or stat.S_IMODE(state.stat().st_mode) != 0o700:
        raise MigrationError("Config backup directory must be private and owned by you")
    previous_umask = os.umask(0o077)
    try:
        batch = Path(tempfile.mkdtemp(prefix="migration-", dir=state))
        staged = batch / "staged"
        backup = batch / "backup"
        staged.mkdir()
        backup.mkdir()
        for root in roots:
            target = staged / root["path"]
            if root.get("kind") == "file":
                target.parent.mkdir(parents=True, exist_ok=True)
            else:
                target.mkdir(parents=True, exist_ok=True)
            transfer(source, root["path"], target, batch)
        check_source()
        for root in roots:
            transfer(source, root["path"], staged / root["path"], batch, verify=True)
        check_source()
        check_destination(home, apps, roots, source.ssh_keys)
        if "ssh" in apps:
            directory = home / ".ssh"
            directory.mkdir(mode=0o700, exist_ok=True)
            directory.chmod(0o700)
            for root in roots:
                if root["app"] == "ssh":
                    (staged / root["path"]).chmod(0o600)
        manifest = batch / "manifest.json"
        completed = []
        manifest.write_text(json.dumps({"apps": apps, "planned": roots, "completed": completed}, indent=2) + "\n")
        for root in roots:
            relative = root["path"]
            target = safe_path(home, relative, root.get("kind", "directory"))
            saved = backup / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            had_target = target.exists()
            if had_target:
                saved.parent.mkdir(parents=True, exist_ok=True)
                move_no_replace(target, saved)
            try:
                move_no_replace(staged / relative, target)
            except (OSError, MigrationError, subprocess.CalledProcessError):
                if had_target and not target.exists() and not target.is_symlink():
                    move_no_replace(saved, target)
                raise
            completed.append(relative)
            manifest.write_text(json.dumps({"apps": apps, "planned": roots, "completed": completed}, indent=2) + "\n")
        print("Config migration verified. Previous settings and manifest: " + str(batch))
        print("No applications started/stopped; source untouched; no private content printed.")
        return batch
    finally:
        os.umask(previous_umask)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, help="Local snapshot HOME or USER@HOST with verified SSH")
    parser.add_argument("--apps", required=True, help=",".join(APPS))
    parser.add_argument("--ssh-control-path", help="Existing source SSH control socket")
    parser.add_argument("--ssh-key", action="append", default=[],
                        help="Explicit SSH identity basename to copy; repeatable, requires --apps ssh")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--include-private-configs", action="store_true")
    args = parser.parse_args(argv)
    apps = parse_apps(args.apps)
    source = Source(args.source, apps, args.ssh_control_path, args.ssh_key)
    migrate(source, apps, Path.home(), args.dry_run, args.include_private_configs)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (MigrationError, OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit("Config migration stopped: " + str(error))
