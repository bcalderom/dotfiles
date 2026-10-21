#!/usr/bin/env python3
"""Opt-in NetBird activation; never copies peer identity or private profiles."""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from urllib.parse import urlsplit


UNITS = {
    "netbird@main.service": "unix:///var/run/netbird/main.sock",
    "netbird.service": "unix:///var/run/netbird.sock",
}
DEFAULT_URL = "https://api.netbird.io:443"


def management_identity(value):
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or parsed.path not in ("", "/")):
        raise ValueError("Management URL must be an HTTPS origin without credentials or query parameters")
    port = parsed.port or 443
    if not 1 <= port <= 65535:
        raise ValueError("Invalid management service port")
    return parsed.hostname.lower(), port


def service_state(unit):
    result = subprocess.run(["systemctl", "show", unit, "-p", "LoadState", "-p", "ActiveState",
                             "-p", "UnitFileState"], text=True, capture_output=True)
    if result.returncode:
        return {}
    return dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)


def select_service():
    states = {unit: service_state(unit) for unit in UNITS}
    active = [unit for unit, state in states.items() if state.get("ActiveState") == "active"]
    if len(active) > 1:
        raise ValueError("Multiple NetBird services are active; review them manually (nothing is stopped)")
    loaded = [unit for unit, state in states.items() if state.get("LoadState") == "loaded"]
    unit = (active or loaded or ["netbird@main.service"])[0]
    return unit, states[unit]


def client_status(address):
    if not shutil.which("netbird"):
        return {}
    result = subprocess.run(["netbird", "--daemon-addr", address, "status", "--json"],
                            text=True, capture_output=True, timeout=20)
    if result.returncode:
        return {}
    try:
        data = json.loads(result.stdout)
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}


def check_existing_peer(status, management_url, hostname):
    management = status.get("management", {})
    if management.get("connected") or status.get("netbirdIp"):
        current_url = management.get("url")
        if not current_url or management_identity(current_url) != management_identity(management_url):
            raise ValueError("Existing peer uses a different management service; refusing to re-register it")
        name = status.get("fqdn", "").split(".")[0]
        if hostname and (not name or name.lower() != hostname.lower()):
            raise ValueError("Existing peer has a different hostname; refusing to change its identity")


def configure(mode, management_url=DEFAULT_URL, hostname=None):
    management_identity(management_url)
    if hostname and not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", hostname):
        raise ValueError("NetBird hostname must be a DNS label of at most 63 characters")
    if mode == "dry-run":
        print("Would select the installed NetBird service, enable/start it and connect to " + management_url)
        print("An existing connected peer is kept; a new peer requires interactive SSO.")
        print("No profile, private key or token is copied; NetBird SSH is not enabled.")
        return 0
    if not shutil.which("systemctl"):
        raise ValueError("NetBird setup requires systemd")
    unit, state = select_service()
    address = UNITS[unit]
    if state.get("LoadState") != "loaded" or not shutil.which("netbird"):
        print("NetBird client/service is missing; install the vpn group first.")
        return 1
    status = client_status(address) if state.get("ActiveState") == "active" else {}
    if state.get("ActiveState") == "active" and not status:
        raise ValueError("Cannot inspect the running daemon; refusing to change an unknown peer")
    check_existing_peer(status, management_url, hostname)
    ready = (state.get("ActiveState") == "active" and state.get("UnitFileState") == "enabled"
             and status.get("management", {}).get("connected") is True)
    if mode == "check":
        print("NetBird service and connection are configured." if ready
              else "NetBird service enablement, activation or login is pending.")
        return int(not ready)
    if os.geteuid() == 0:
        raise ValueError("Run NetBird setup as the desktop user, not root")
    if not status.get("management", {}).get("connected") and not sys.stdin.isatty():
        raise ValueError("Connecting a new/disconnected peer requires an interactive terminal for SSO")
    if state.get("UnitFileState") != "enabled":
        subprocess.run(["sudo", "systemctl", "enable", unit], check=True)
    if state.get("ActiveState") != "active":
        subprocess.run(["sudo", "systemctl", "start", unit], check=True)
    status = client_status(address)
    if not status:
        raise ValueError("Cannot inspect the started daemon; complete service diagnosis before login")
    check_existing_peer(status, management_url, hostname)
    if not status.get("management", {}).get("connected"):
        command = ["netbird", "--daemon-addr", address, "up", "--management-url", management_url]
        if hostname:
            command += ["--hostname", hostname]
        # Authentication stays in the user's terminal, never in a saved manifest.
        subprocess.run(command, check=True)
    return configure("check", management_url, hostname)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    for mode in ("dry-run", "check", "apply"):
        modes.add_argument("--" + mode, dest="mode", action="store_const", const=mode)
    parser.add_argument("--management-url", default=DEFAULT_URL)
    parser.add_argument("--hostname")
    args = parser.parse_args(argv)
    try:
        return configure(args.mode or "dry-run", args.management_url, args.hostname)
    except (ValueError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        # Do not echo command output or authentication material on failure.
        print("NetBird setup stopped. Check the service, existing peer settings and interactive login.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
