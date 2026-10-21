# NetBird setup

Explicit, repeatable NetBird activation for Arch. Default and `--dry-run` modes do
not inspect private profiles, start services or connect to the VPN. `--check` only
queries service state and the daemon's status API.

```bash
python3 scripts/network/netbird-setup/configure_netbird.py --dry-run
python3 scripts/network/netbird-setup/configure_netbird.py --apply
python3 scripts/network/netbird-setup/configure_netbird.py --check
```

Normally use `bash setup.sh --only vpn --aur yay --configure-netbird`. The vpn
group includes the CLI and official desktop GUI (`netbird-ui-bin`, from AUR).
Review AUR builds first. `--enable-services` alone still never activates NetBird.

The helper prefers an already active service; otherwise it selects Arch's
`netbird@main.service` (or a loaded legacy `netbird.service`). Multiple active
daemons are rejected rather than stopped. Explicit apply enables and starts only
the selected daemon; it never restarts an active service, installs a second one
with `netbird service install`, or changes an existing peer's identity.

For a fresh device, run in an interactive terminal as the normal desktop user.
Authenticate sudo/SSO yourself, using the same NetBird account and organization as
the old machine. No setup keys, passwords or browser codes are saved by this
helper. The management URL defaults to NetBird Cloud. A self-hosted HTTPS origin
can be supplied with `--management-url`; credentials/query parameters are rejected.
Choose `--hostname` before first registration. An existing assigned/connected peer
with a different management URL or hostname is refused, not silently re-enrolled.

Do **not** copy `/etc/netbird`, `/var/lib/netbird`, old client profile/state JSON,
WireGuard keys or setup tokens from the original machine. That would clone the
peer identity and prevent concurrent use. Access policies come from NetBird's
management server; a new peer may need an administrator to assign groups/approval.
The helper does not enable NetBird's SSH server or relax host-key checks.

Tests use mocked commands; no real service, key, VPN or login is touched:

```bash
python3 -B scripts/network/netbird-setup/tests/test_configure_netbird.py
```
