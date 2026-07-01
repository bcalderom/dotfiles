# install-brother-t720dw

## Purpose

Install and configure Brother DCP-T720DW printing/scanning support on Arch Linux.

The installer uses driverless IPP (`-m everywhere`) for printing and optional SANE/AirScan packages for scanning.

## Usage

```bash
python install_brother_t720dw.py
python install_brother_t720dw.py --ip 192.168.1.50
python install_brother_t720dw.py --ip 192.168.1.50 --skip-scanner --skip-test-print
```

## Service Behavior

This installer does not enable `cups.service` or `avahi-daemon.service`.

After package installation succeeds, it only starts those services for setup and test printing:

```bash
systemctl start cups.service avahi-daemon.service
```

Use the printing service helper under `~/dotfiles/scripts/printing` for ongoing service management:

```bash
psvc status
psvc start
psvc stop
psvc doctor --queue brother_t720dw
```

## Tests

```bash
bash tests/test-install-brother-t720dw.sh
```
