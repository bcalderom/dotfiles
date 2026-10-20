# hypr-lid-deploy

## Purpose

Deploy Hyprland lid handling scripts and the user systemd service.

`configure-host.sh` additionally reproduces the reference host's always-awake
lid policy, with local hardware detection. It is used by `setup.sh --configure-lid`.

## Usage

```bash
hypr-lid-deploy.sh --install
hypr-lid-deploy.sh --update
bash scripts/desktop/hypr-lid-deploy/configure-host.sh --dry-run
bash scripts/desktop/hypr-lid-deploy/configure-host.sh --apply
bash scripts/desktop/hypr-lid-deploy/configure-host.sh --check
```

Run the `configure-host.sh` examples from the checkout as the desktop user, never
root. `--apply` requests sudo for `/etc/systemd/logind.conf.d/60-dotfiles-lid.conf`
and a logind reload; it writes a per-host `20-local-hardware.conf` user drop-in and
enables/restarts only `hypr-lid.service`. The existing direct install/update
commands still deploy the display scripts alone, not the sleep policy.

Detection requires one readable `/proc/acpi/button/lid/*/state`. Backlight selection
prefers one `raw` device under `/sys/class/backlight`, otherwise one device total.
Set `LID_STATE_PATH` / `HYPR_LID_BACKLIGHT_DEVICE` explicitly if ambiguous. Existing
different managed files or legacy `hypr-lid.path` require review before applying.
Hardware drop-ins are excluded from Stow; never copy them between machines.

The machine stays awake when closed on battery, AC and dock. Watch battery drain
and cooling; never store it running in a bag. The helper never restarts Hyprland,
logind or the login session. Runtime checks cannot replace a physical lid/display
test. Checks/previews do not change files or services. Alternate `LID_DEST_ROOT`,
`LID_PROC_ROOT` and `LID_BACKLIGHT_ROOT` values are for isolated tests only.

## Tests

```bash
bash tests/test-deploy.sh
bash tests/test-lid.sh
bash tests/test-lid-watch.sh
bash tests/test-configure-host.sh
```
