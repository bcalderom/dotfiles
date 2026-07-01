"""Shared CUPS helpers for Brother printer installers on Arch Linux."""

from __future__ import annotations

import ipaddress
import os
import re
import shutil
import socket
import subprocess
from typing import Iterable, Sequence


PRINT_PACKAGES = ["cups", "cups-filters", "ghostscript", "avahi", "nss-mdns"]
SETUP_SERVICES = ["cups.service", "avahi-daemon.service"]


def run(
    cmd: Sequence[str], check: bool = True, capture: bool = False, sudo: bool = False
) -> subprocess.CompletedProcess[str]:
    full_cmd = list(cmd)
    if sudo and os.geteuid() != 0:
        sudo_cmd = os.environ.get("SUDO", "sudo")
        if sudo_cmd:
            full_cmd = [sudo_cmd, *full_cmd]

    return subprocess.run(
        full_cmd,
        check=check,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def require_binary(name: str) -> None:
    if shutil.which(name) is None:
        raise RuntimeError(f"Missing required command: {name}")


def verify_binaries(names: Iterable[str]) -> None:
    missing = [name for name in names if shutil.which(name) is None]
    if missing:
        raise RuntimeError(
            f"Required commands are missing from PATH: {', '.join(missing)}"
        )


def missing_packages(packages: Iterable[str]) -> list[str]:
    missing: list[str] = []
    for package in packages:
        cp = run(["pacman", "-Q", package], check=False, capture=True)
        if cp.returncode != 0:
            missing.append(package)
    return missing


def verify_installed_packages(packages: Iterable[str]) -> None:
    missing = missing_packages(packages)
    if missing:
        raise RuntimeError(f"Required packages are not installed: {', '.join(missing)}")


def install_pacman_packages(packages: Iterable[str], noconfirm: bool = True) -> None:
    cmd = ["pacman", "-S", "--needed"]
    if noconfirm:
        cmd.append("--noconfirm")
    cmd.extend(packages)
    run(cmd, sudo=True)


def detect_aur_helper() -> str:
    for helper in ("yay", "paru"):
        if shutil.which(helper) is not None:
            return helper
    raise RuntimeError("Install yay or paru before installing AUR package: brlaser")


def install_aur_packages(
    packages: Iterable[str], helper: str | None = None, noconfirm: bool = True
) -> None:
    missing = missing_packages(packages)
    if not missing:
        return
    if os.geteuid() == 0:
        raise RuntimeError("AUR packages must be installed as a non-root user")

    aur_helper = helper or detect_aur_helper()
    require_binary(aur_helper)
    cmd = [aur_helper, "-S", "--needed"]
    if noconfirm:
        cmd.append("--noconfirm")
    cmd.extend(missing)
    run(cmd)


def start_setup_services(services: Iterable[str] = SETUP_SERVICES) -> None:
    run(["systemctl", "start", *services], sudo=True)


def validate_ipv4_address(raw: str) -> str:
    try:
        ipaddress.IPv4Address(raw)
    except ValueError as exc:
        raise RuntimeError(f"Invalid IPv4 address: {raw}") from exc
    return raw


def get_local_subnets() -> list[ipaddress.IPv4Network]:
    cp = run(["ip", "-4", "route", "show"], capture=True)
    nets: list[ipaddress.IPv4Network] = []
    for line in cp.stdout.splitlines():
        match = re.match(r"^(\d+\.\d+\.\d+\.\d+/\d+)\s+dev\s+\S+\s+proto\s+kernel", line)
        if not match:
            continue
        try:
            nets.append(ipaddress.IPv4Network(match.group(1), strict=False))
        except ValueError:
            continue
    return nets


def probe_ports(ip: str, ports: Iterable[int], timeout: float = 0.2) -> list[int]:
    open_ports: list[int] = []
    for port in ports:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        try:
            sock.connect((ip, port))
            open_ports.append(port)
        except OSError:
            pass
        finally:
            sock.close()
    return open_ports


def discover_with_avahi(services: Iterable[str] = ("_ipp._tcp",)) -> list[str]:
    if shutil.which("avahi-browse") is None:
        return []

    ips: list[str] = []
    for service in services:
        cp = run(["avahi-browse", "-rt", service], capture=True, check=False)
        for line in cp.stdout.splitlines():
            if not line.startswith("="):
                continue
            parts = line.split(";")
            if len(parts) < 8:
                continue
            ip = parts[7].strip()
            try:
                ipaddress.IPv4Address(ip)
            except ValueError:
                continue
            ips.append(ip)
    return sorted(set(ips))


def discover_with_port_scan(
    required_ports: Iterable[int],
    probe_port_list: Iterable[int] = (631, 9100, 515),
    max_subnet_addresses: int = 512,
) -> list[str]:
    candidates: list[str] = []
    required = set(required_ports)
    for subnet in get_local_subnets():
        if subnet.num_addresses > max_subnet_addresses:
            continue
        for host in subnet.hosts():
            ip = str(host)
            open_ports = set(probe_ports(ip, probe_port_list, timeout=0.12))
            if required.issubset(open_ports):
                candidates.append(ip)
    return sorted(set(candidates))


def choose_ip(ips: list[str]) -> str:
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


def discover_printer_ip(required_ports: Iterable[int]) -> str:
    avahi_ips = discover_with_avahi(("_ipp._tcp", "_printer._tcp"))
    scan_ips = discover_with_port_scan(required_ports)
    return choose_ip(sorted(set(avahi_ips + scan_ips)))


def configure_driverless_ipp_queue(ip: str, queue: str) -> str:
    uris = [f"ipp://{ip}/ipp/print", f"ipp://{ip}/ipp"]
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
        f"Last error: {last_err}"
    )


def find_cups_model(patterns: Iterable[str]) -> str:
    cp = run(["lpinfo", "-m"], capture=True)
    lowered_patterns = [pattern.lower() for pattern in patterns]
    for line in cp.stdout.splitlines():
        lowered = line.lower()
        if all(pattern in lowered for pattern in lowered_patterns):
            return line.split()[0]
    raise RuntimeError(
        "Unable to find a CUPS model matching: " + ", ".join(patterns)
    )


def configure_model_queue(queue: str, uri: str, model: str) -> None:
    run(["lpadmin", "-x", queue], check=False, sudo=True)
    cp = run(
        ["lpadmin", "-p", queue, "-E", "-v", uri, "-m", model],
        check=False,
        capture=True,
        sudo=True,
    )
    if cp.returncode != 0:
        raise RuntimeError((cp.stderr or "Failed to create CUPS queue").strip())
    run(["lpoptions", "-d", queue], sudo=True)


def verify_printing(queue: str, submit_test: bool = True) -> None:
    run(["lpstat", "-t"], check=False)
    if submit_test:
        run(["lp", "-d", queue, "/etc/hosts"], check=False)


def verify_scanning() -> None:
    run(["scanimage", "-L"], check=False)
