#!/usr/bin/env python3
"""Install and configure Brother DCP-T720DW on Arch Linux over Wi-Fi.

What it does:
1) Installs required print packages
2) Enables and starts CUPS + Avahi
3) Auto-discovers printer IP (or uses --ip)
4) Creates a CUPS queue using driverless IPP
5) Optionally installs scanner packages

Run:
  python scripts/install_brother_t720dw.py
"""

from __future__ import annotations

import argparse
import ipaddress
import os
import re
import shutil
import socket
import subprocess
import sys
from typing import Iterable, List, Optional


PRINT_PACKAGES = ["cups", "cups-filters", "ghostscript", "avahi", "nss-mdns"]
SCAN_PACKAGES = ["sane", "sane-airscan", "simple-scan"]
DEFAULT_QUEUE = "brother_t720dw"


def run(
    cmd: List[str], check: bool = True, capture: bool = False, sudo: bool = False
) -> subprocess.CompletedProcess:
    if sudo and os.geteuid() != 0:
        cmd = ["sudo", *cmd]
    return subprocess.run(
        cmd,
        check=check,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def require_binary(name: str) -> None:
    if shutil.which(name) is None:
        print(f"Missing required command: {name}")
        sys.exit(1)


def install_packages(packages: Iterable[str]) -> None:
    run(["pacman", "-S", "--needed", "--noconfirm", *packages], sudo=True)


def verify_installed_packages(packages: Iterable[str]) -> None:
    missing: List[str] = []
    for package in packages:
        cp = run(["pacman", "-Q", package], check=False, capture=True)
        if cp.returncode != 0:
            missing.append(package)
    if missing:
        raise RuntimeError(f"Required packages are not installed: {', '.join(missing)}")


def verify_binaries(names: Iterable[str]) -> None:
    missing = [name for name in names if shutil.which(name) is None]
    if missing:
        raise RuntimeError(
            f"Required commands are missing from PATH: {', '.join(missing)}"
        )


def enable_services() -> None:
    run(
        ["systemctl", "enable", "--now", "cups.service", "avahi-daemon.service"],
        sudo=True,
    )


def get_local_subnets() -> List[ipaddress.IPv4Network]:
    cp = run(["ip", "-4", "route", "show"], capture=True)
    nets: List[ipaddress.IPv4Network] = []
    for line in cp.stdout.splitlines():
        m = re.match(r"^(\d+\.\d+\.\d+\.\d+/\d+)\s+dev\s+\S+\s+proto\s+kernel", line)
        if not m:
            continue
        try:
            net = ipaddress.ip_network(m.group(1), strict=False)
            if isinstance(net, ipaddress.IPv4Network):
                nets.append(net)
        except ValueError:
            continue
    return nets


def probe_ports(ip: str, ports: Iterable[int], timeout: float = 0.2) -> List[int]:
    open_ports: List[int] = []
    for port in ports:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        try:
            s.connect((ip, port))
            open_ports.append(port)
        except OSError:
            pass
        finally:
            s.close()
    return open_ports


def discover_with_avahi() -> List[str]:
    if shutil.which("avahi-browse") is None:
        return []
    try:
        cp = run(["avahi-browse", "-rt", "_ipp._tcp"], capture=True, check=False)
    except Exception:
        return []

    ips: List[str] = []
    for line in cp.stdout.splitlines():
        # example line:
        # =;wlan0;IPv4;Brother DCP-T720DW;_ipp._tcp;local;host.local;192.168.1.50;631;
        if not line.startswith("="):
            continue
        parts = line.split(";")
        if len(parts) < 9:
            continue
        ip = parts[7].strip()
        try:
            ipaddress.ip_address(ip)
            ips.append(ip)
        except ValueError:
            continue
    return sorted(set(ips))


def discover_with_port_scan() -> List[str]:
    candidates: List[str] = []
    for subnet in get_local_subnets():
        if subnet.num_addresses > 512:
            continue
        for host in subnet.hosts():
            ip = str(host)
            open_ports = probe_ports(ip, (631, 9100, 515), timeout=0.12)
            if 631 in open_ports and 9100 in open_ports:
                candidates.append(ip)
    return sorted(set(candidates))


def choose_ip(ips: List[str]) -> str:
    if not ips:
        raise RuntimeError("No printer IP discovered automatically.")
    if len(ips) == 1:
        return ips[0]

    print("Multiple printer candidates found:")
    for idx, ip in enumerate(ips, start=1):
        print(f"  {idx}) {ip}")
    while True:
        raw = input("Select printer number: ").strip()
        if raw.isdigit() and 1 <= int(raw) <= len(ips):
            return ips[int(raw) - 1]
        print("Invalid selection.")


def configure_cups_queue(ip: str, queue: str) -> str:
    uris = [
        f"ipp://{ip}/ipp/print",
        f"ipp://{ip}/ipp",
    ]

    run(["lpadmin", "-x", queue], check=False, sudo=True)

    last_err = ""
    for uri in uris:
        cp = run(
            ["lpadmin", "-p", queue, "-E", "-v", uri, "-m", "everywhere"],
            check=False,
            capture=True,
            sudo=True,
        )
        if cp.returncode == 0:
            run(["lpoptions", "-d", queue], sudo=True)
            return uri
        last_err = (cp.stderr or "").strip()

    raise RuntimeError(
        "Failed to create CUPS queue with driverless IPP. "
        "Install Brother LPR/CUPSWrapper drivers from AUR as fallback. "
        f"Last error: {last_err}"
    )


def verify_printing(queue: str) -> None:
    run(["lpstat", "-t"], check=False)
    run(["lp", "-d", queue, "/etc/hosts"], check=False)


def verify_scanning() -> None:
    run(["scanimage", "-L"], check=False)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Install Brother DCP-T720DW over Wi-Fi on Arch Linux"
    )
    parser.add_argument(
        "--ip", help="Printer IP address. If omitted, autodiscovery is used."
    )
    parser.add_argument(
        "--queue",
        default=DEFAULT_QUEUE,
        help=f"CUPS queue name (default: {DEFAULT_QUEUE})",
    )
    parser.add_argument(
        "--skip-scanner",
        action="store_true",
        help="Configure printing only; skip scanner package setup.",
    )
    args = parser.parse_args()

    for binary in ("pacman", "systemctl", "ip"):
        require_binary(binary)

    print("[1/6] Installing print packages...")
    install_packages(PRINT_PACKAGES)
    verify_installed_packages(PRINT_PACKAGES)
    verify_binaries(("lpadmin", "lpoptions", "lpstat", "lp"))

    print("[2/6] Enabling CUPS and Avahi...")
    enable_services()

    if args.ip:
        printer_ip = args.ip
    else:
        print("[3/6] Auto-discovering printer IP (avahi + port scan)...")
        avahi_ips = discover_with_avahi()
        scan_ips = discover_with_port_scan()
        merged = sorted(set(avahi_ips + scan_ips))
        printer_ip = choose_ip(merged)

    print(f"Using printer IP: {printer_ip}")

    print("[4/6] Configuring CUPS queue...")
    uri = configure_cups_queue(printer_ip, args.queue)
    print(f"Configured queue '{args.queue}' with URI: {uri}")

    print("[5/6] Verifying printing (submits /etc/hosts as a test print)...")
    verify_printing(args.queue)

    if not args.skip_scanner:
        print("[6/6] Installing scanner packages and verifying detection...")
        install_packages(SCAN_PACKAGES)
        verify_installed_packages(SCAN_PACKAGES)
        verify_binaries(("scanimage",))
        verify_scanning()
    else:
        print("[6/6] Scanner setup skipped (--skip-scanner)")

    print("Done.")
    print("Recommendation: reserve this printer IP in your router DHCP settings.")


if __name__ == "__main__":
    main()
