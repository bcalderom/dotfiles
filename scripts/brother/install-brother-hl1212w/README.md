# install-brother-hl1212w

## Purpose

Install and configure Brother HL-1212W printing support on Arch Linux.

The installer uses the `brlaser` AUR package and the `Brother HL-1210W series` CUPS model, which covers the HL-1212W model family.

## Usage

```bash
python install_brother_hl1212w.py --ip 192.168.1.51
python install_brother_hl1212w.py --ip 192.168.1.51 --skip-test-print
python install_brother_hl1212w.py --uri socket://192.168.1.51:9100
```

If both `yay` and `paru` are installed, choose one explicitly:

```bash
python install_brother_hl1212w.py --ip 192.168.1.51 --aur-helper yay
```

By default, package installs pass `--noconfirm`. Use `--confirm` to allow package-manager prompts.

## Service Behavior

This installer does not enable `cups.service` or `avahi-daemon.service`.

After package and driver installation succeeds, it only starts those services for setup and test printing:

```bash
systemctl start cups.service avahi-daemon.service
```

Use the printing service helper under `~/dotfiles/scripts/printing` for ongoing service management:

```bash
psvc status
psvc start
psvc stop
psvc doctor --queue brother_hl1212w
```

## Tests

```bash
bash tests/test-install-brother-hl1212w.sh
```
