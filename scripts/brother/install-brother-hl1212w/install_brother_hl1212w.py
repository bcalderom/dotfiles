#!/usr/bin/env python3
"""Install and configure Brother HL-1212W on Arch Linux over Wi-Fi."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from brother_cups import (  # noqa: E402
    PRINT_PACKAGES,
    configure_model_queue,
    discover_printer_ip,
    find_cups_model,
    install_aur_packages,
    install_pacman_packages,
    require_binary,
    start_setup_services,
    validate_ipv4_address,
    verify_binaries,
    verify_installed_packages,
    verify_printing,
)


BRLASER_PACKAGE = "brlaser"
DEFAULT_QUEUE = "brother_hl1212w"
MODEL_PATTERNS = ("brlaser", "hl-1210w")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Install Brother HL-1212W over Wi-Fi on Arch Linux"
    )
    parser.add_argument(
        "--ip", help="Printer IPv4 address. If omitted, autodiscovery is used."
    )
    parser.add_argument(
        "--uri",
        help="Complete CUPS device URI. Overrides --ip, for example socket://192.168.1.51:9100.",
    )
    parser.add_argument(
        "--queue",
        default=DEFAULT_QUEUE,
        help=f"CUPS queue name (default: {DEFAULT_QUEUE})",
    )
    parser.add_argument(
        "--aur-helper",
        choices=("yay", "paru"),
        help="AUR helper to use for brlaser. Defaults to yay, then paru.",
    )
    parser.add_argument(
        "--confirm",
        action="store_true",
        help="Do not pass --noconfirm to pacman/AUR helper installs.",
    )
    parser.add_argument(
        "--skip-test-print",
        action="store_true",
        help="Do not submit /etc/hosts as a test print after queue setup.",
    )
    args = parser.parse_args()

    for binary in ("pacman", "systemctl"):
        require_binary(binary)
    if not args.ip and not args.uri:
        require_binary("ip")

    noconfirm = not args.confirm

    print("[1/5] Installing print packages...")
    install_pacman_packages(PRINT_PACKAGES, noconfirm=noconfirm)
    verify_installed_packages(PRINT_PACKAGES)

    print("[2/5] Installing brlaser from AUR...")
    install_aur_packages(
        [BRLASER_PACKAGE], helper=args.aur_helper, noconfirm=noconfirm
    )
    verify_installed_packages([BRLASER_PACKAGE])
    verify_binaries(("lpadmin", "lpinfo", "lpoptions", "lpstat", "lp"))

    print("[3/5] Starting CUPS and Avahi for setup/testing (not enabling)...")
    start_setup_services()

    if args.uri:
        uri = args.uri
    else:
        if args.ip:
            printer_ip = validate_ipv4_address(args.ip)
        else:
            print("Auto-discovering printer IP (avahi + port scan)...")
            printer_ip = discover_printer_ip(required_ports=(9100,))
        uri = f"socket://{printer_ip}:9100"

    print(f"Using printer URI: {uri}")

    print("[4/5] Configuring CUPS queue with brlaser...")
    model = find_cups_model(MODEL_PATTERNS)
    configure_model_queue(args.queue, uri, model)
    print(f"Configured queue '{args.queue}' with model: {model}")

    print("[5/5] Verifying printing...")
    verify_printing(args.queue, submit_test=not args.skip_test_print)

    print("Done.")
    print("Recommendation: reserve this printer IP in your router DHCP settings.")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
