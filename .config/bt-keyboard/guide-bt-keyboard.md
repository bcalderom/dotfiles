# Auto-connect Bluetooth Keyboard with systemd (Arch Linux)

This guide sets up a systemd service that automatically connects a Bluetooth keyboard at boot (and reconnects it after resume), using `bluetoothctl`.

It includes:
- a one-time pairing/trusting step
- an environment file storing the keyboard MAC
- a systemd service (with retries for reliability)
- an **automated option** that copies/deploys the files from `~/.config/bt-keyboard/`

---

## Overview

You will end up with these source files in your home directory:

```
~/.config/bt-keyboard/
├── autoconnect.env
├── bt-keyboard.service
├── bt-keyboard.system-sleep
└── bt-keyboard-deploy.sh
```

And these deployed system files:

- `/etc/bluetooth/autoconnect.env`
- `/etc/systemd/system/bt-keyboard.service`
- `/etc/systemd/system-sleep/bt-keyboard`

---

## Prerequisites (Arch)

Install Bluetooth stack:

```bash
sudo pacman -S --needed bluez bluez-utils
```

Enable and start Bluetooth:

```bash
sudo systemctl enable --now bluetooth.service
```

Confirm `bluetoothctl` exists:

```bash
bluetoothctl --version
```

---

## Step 1: Pair and Trust the Keyboard (One Time)

The service **does not pair** devices — it only connects them. Do this once.

Run:

```bash
bluetoothctl
```

In the interactive shell:

```text
power on
agent on
default-agent
scan on
```

Put your keyboard in pairing mode. When it appears, use its MAC address:

```text
pair AA:BB:CC:DD:EE:FF
trust AA:BB:CC:DD:EE:FF
connect AA:BB:CC:DD:EE:FF
quit
```

Verify:

```bash
bluetoothctl info AA:BB:CC:DD:EE:FF
```

---

## Step 2: Create the Local Config Files (vim)

Create the folder:

```bash
mkdir -p ~/.config/bt-keyboard
```

### 2.1 Create `~/.config/bt-keyboard/autoconnect.env`

```bash
vim ~/.config/bt-keyboard/autoconnect.env
```

Paste (replace MAC):

```bash
BT_DEVICE_MAC=AA:BB:CC:DD:EE:FF
```

Optional (recommended) permissions:

```bash
chmod 600 ~/.config/bt-keyboard/autoconnect.env
```

### 2.2 Create `~/.config/bt-keyboard/bt-keyboard.service`

```bash
vim ~/.config/bt-keyboard/bt-keyboard.service
```

Paste:

```ini
[Unit]
Description=Auto-connect Bluetooth keyboard
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=oneshot
# Use the system-level env file after deployment (see automation section)
EnvironmentFile=/etc/bluetooth/autoconnect.env

# Retry loop: handles cases where bluetooth is up but the adapter/device isn't ready yet.
ExecStart=/usr/bin/bash -ceu '/usr/bin/bluetoothctl power on >/dev/null 2>&1 || true; for i in {1..10}; do /usr/bin/bluetoothctl connect "${BT_DEVICE_MAC}" && exit 0; sleep 0.5; done; exit 0'
TimeoutStartSec=8s

[Install]
WantedBy=multi-user.target
```

---

## Step 3: Automated Deployment (Copy These Files Into Place)

This section copies:
- `~/.config/bt-keyboard/autoconnect.env` → `/etc/bluetooth/autoconnect.env`
- `~/.config/bt-keyboard/bt-keyboard.service` → `/etc/systemd/system/bt-keyboard.service`
- `~/.config/bt-keyboard/bt-keyboard.system-sleep` → `/etc/systemd/system-sleep/bt-keyboard`

### Option A: One-liner deploy + enable + start

```bash
sudo install -d -m 0755 /etc/bluetooth /etc/systemd/system /etc/systemd/system-sleep && \
sudo install -m 0600 ~/.config/bt-keyboard/autoconnect.env /etc/bluetooth/autoconnect.env && \
sudo install -m 0644 ~/.config/bt-keyboard/bt-keyboard.service /etc/systemd/system/bt-keyboard.service && \
sudo install -m 0755 ~/.config/bt-keyboard/bt-keyboard.system-sleep /etc/systemd/system-sleep/bt-keyboard && \
sudo systemctl daemon-reload && \
sudo systemctl enable --now bt-keyboard.service
```

### Option B: Small deploy script (recommended)

Create:

```bash
vim ~/.config/bt-keyboard/bt-keyboard-deploy.sh
```

Paste:

```bash
#!/usr/bin/env bash
set -euo pipefail

MODE="install"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      MODE="install"
      shift
      ;;
    --update)
      MODE="update"
      shift
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--install|--update]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

SRC_DIR="${HOME}/.config/bt-keyboard"
ENV_SRC="${SRC_DIR}/autoconnect.env"
SVC_SRC="${SRC_DIR}/bt-keyboard.service"
SLEEP_SRC="${SRC_DIR}/bt-keyboard.system-sleep"

ENV_DST_DIR="/etc/bluetooth"
ENV_DST="${ENV_DST_DIR}/autoconnect.env"
SVC_DST="/etc/systemd/system/bt-keyboard.service"
SLEEP_DST_DIR="/etc/systemd/system-sleep"
SLEEP_DST="${SLEEP_DST_DIR}/bt-keyboard"

if [[ ! -f "${ENV_SRC}" ]]; then
  echo "Missing: ${ENV_SRC}"
  exit 1
fi

if [[ ! -f "${SVC_SRC}" ]]; then
  echo "Missing: ${SVC_SRC}"
  exit 1
fi

if [[ ! -f "${SLEEP_SRC}" ]]; then
  echo "Missing: ${SLEEP_SRC}"
  exit 1
fi

sudo install -d -m 0755 "${ENV_DST_DIR}" /etc/systemd/system "${SLEEP_DST_DIR}"
sudo install -m 0600 "${ENV_SRC}" "${ENV_DST}"
sudo install -m 0644 "${SVC_SRC}" "${SVC_DST}"
sudo install -m 0755 "${SLEEP_SRC}" "${SLEEP_DST}"

sudo systemctl daemon-reload
if [[ "${MODE}" == "install" ]]; then
  sudo systemctl enable --now bt-keyboard.service
else
  sudo systemctl restart bt-keyboard.service
fi

echo "Deployed:"
echo "  ${ENV_DST}"
echo "  ${SVC_DST}"
echo "  ${SLEEP_DST}"
echo
echo "Status:"
systemctl --no-pager status bt-keyboard.service || true
```

Make executable and run:

```bash
chmod +x ~/.config/bt-keyboard/bt-keyboard-deploy.sh
~/.config/bt-keyboard/bt-keyboard-deploy.sh --install
```

To update an existing install after editing `autoconnect.env` or the unit file:

```bash
~/.config/bt-keyboard/bt-keyboard-deploy.sh --update
```

---

## Step 4: Verify

Check service status:

```bash
systemctl status bt-keyboard.service
```

Note: this unit is `Type=oneshot`, so after a successful run it may show as `inactive (dead)`. Use logs to confirm it ran.

Confirm the keyboard is connected:

```bash
bluetoothctl info "$(grep -E '^BT_DEVICE_MAC=' /etc/bluetooth/autoconnect.env | cut -d= -f2)"
```

---

## Troubleshooting

### 1) Service ran but keyboard isn’t connected
- Ensure the keyboard is powered on and in range
- Ensure it was `trust`ed:

```bash
bluetoothctl info AA:BB:CC:DD:EE:FF
```

Look for “Trusted: yes”.

### 2) Bluetooth comes up slowly at boot
Increase retries and/or sleep:

In `/etc/systemd/system/bt-keyboard.service` change:

- `{1..10}` → `{1..20}`
- `sleep 0.5` → `sleep 1`

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl restart bt-keyboard.service
```

### 3) Debug the connect command manually
Try:

```bash
source /etc/bluetooth/autoconnect.env
bluetoothctl connect "$BT_DEVICE_MAC"
```

---

## Uninstall / Disable

Disable:

```bash
sudo systemctl disable --now bt-keyboard.service
```

Remove files:

```bash
sudo rm -f /etc/systemd/system/bt-keyboard.service
sudo rm -f /etc/systemd/system-sleep/bt-keyboard
sudo rm -f /etc/bluetooth/autoconnect.env
sudo systemctl daemon-reload
```

Optional: remove local config folder:

```bash
rm -rf ~/.config/bt-keyboard
```

---

## Final File Tree (Local)

Expected:

```text
~/.config/bt-keyboard
├── autoconnect.env
├── bt-keyboard.service
├── bt-keyboard.system-sleep
└── bt-keyboard-deploy.sh
```
