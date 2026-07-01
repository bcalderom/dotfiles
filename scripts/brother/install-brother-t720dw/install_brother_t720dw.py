#!/usr/bin/env python3
"""Install and configure Brother DCP-T720DW on Arch Linux over Wi-Fi."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from brother_cups import (  # noqa: E402
    PRINT_PACKAGES,
    configure_driverless_ipp_queue,
    discover_printer_ip,
    install_pacman_packages,
    require_binary,
    start_setup_services,
    validate_ipv4_address,
    verify_binaries,
    verify_installed_packages,
    verify_printing,
    verify_scanning,
)


SCAN_PACKAGES = ["sane", "sane-airscan", "simple-scan"]
DEFAULT_QUEUE = "brother_t720dw"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Install Brother DCP-T720DW over Wi-Fi on Arch Linux"
    )
    parser.add_argument(
        "--ip", help="Printer IPv4 address. If omitted, autodiscovery is used."
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
    parser.add_argument(
        "--skip-test-print",
        action="store_true",
        help="Do not submit /etc/hosts as a test print after queue setup.",
    )
    args = parser.parse_args()

    for binary in ("pacman", "systemctl", "ip"):
        require_binary(binary)

    print("[1/6] Installing print packages...")
    install_pacman_packages(PRINT_PACKAGES)
    verify_installed_packages(PRINT_PACKAGES)
    verify_binaries(("lpadmin", "lpoptions", "lpstat", "lp"))

    if not args.skip_scanner:
        print("[2/6] Installing scanner packages...")
        install_pacman_packages(SCAN_PACKAGES)
        verify_installed_packages(SCAN_PACKAGES)
        verify_binaries(("scanimage",))
    else:
        print("[2/6] Scanner package setup skipped (--skip-scanner)")

    print("[3/6] Starting CUPS and Avahi for setup/testing (not enabling)...")
    start_setup_services()

    if args.ip:
        printer_ip = validate_ipv4_address(args.ip)
    else:
        print("[4/6] Auto-discovering printer IP (avahi + port scan)...")
        printer_ip = discover_printer_ip(required_ports=(631, 9100))

    print(f"Using printer IP: {printer_ip}")

    print("[4/6] Configuring CUPS queue...")
    uri = configure_driverless_ipp_queue(printer_ip, args.queue)
    print(f"Configured queue '{args.queue}' with URI: {uri}")

    print("[5/6] Verifying printing...")
    verify_printing(args.queue, submit_test=not args.skip_test_print)

    if not args.skip_scanner:
        print("[6/6] Verifying scanner detection...")
        verify_scanning()
    else:
        print("[6/6] Scanner setup skipped (--skip-scanner)")

    print("Done.")
    print("Recommendation: reserve this printer IP in your router DHCP settings.")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
