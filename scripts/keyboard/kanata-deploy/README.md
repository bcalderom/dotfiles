# kanata-deploy

## Purpose

Deploy Kanata keyboard configuration and systemd service files.

## Usage

```bash
kanata-deploy.sh --install
kanata-deploy.sh --update
kanata-deploy.sh --activate
kanata-deploy.sh --check
```

`setup.sh --deploy-kanata` uses `--activate`: validate with `kanata --check`, deploy
the system unit/config and persistent `uinput` module, then enable and restart the
service exactly once. This explicitly authorizes applying the keyboard mapping;
it does not add the desktop user to `input`. Different existing system files
require review/backups before an explicit manual `--update`.

`--check` only validates the source profile, compares deployed files and checks
whether the system service is enabled/active. It never invokes sudo, writes files
or grabs a keyboard. Keep the existing `--install` / `--update` entrypoints for
manual deployment. Use `setup.sh --dry-run --deploy-kanata` for a preview.

## Tests

```bash
bash tests/test-kanata-deploy.sh
```
