# Troubleshooting

## Browser And Terminal Open On Workspace 1

Likely cause:

- Hyprland workspace-targeted `exec-once` rules are missing or not reloaded.
- The app restored an existing session/window before the workspace rule applied.

Checks:

```bash
hyprctl clients
hyprctl workspaces
```

Preferred fix:

- Keep browser and terminal startup in native Hyprland `exec-once = [workspace ... silent]` rules.
- Restart the Hyprland session after changing startup rules.

## Docked Monitor Does Not Become Primary

Likely causes:

- Kanshi did not select `docked_dp_only` or `docked_dp_hdmi`.
- Monitor identifier changed after an update.
- `DP-1` is not the active connector name anymore.

Checks:

```bash
hyprctl monitors
kanshictl status
```

Fix path:

- Compare live identifiers with `hardware-and-identifiers.md`.
- Update `~/.config/kanshi/config` aliases if the descriptor changed.

## Lid Closed But Internal Display Stays Enabled

Likely causes:

- Hyprland did not receive the lid switch event.
- `~/.config/hypr/scripts/lid.sh` did not see `DP-1`.
- Kanshi stayed on the `laptop` profile and re-enabled `eDP-1`.
- Workspace `2` was not moved to `DP-1` before disabling `eDP-1`.
- A stale systemd lid unit caused confusion.

Checks:

```bash
hyprctl devices
hyprctl monitors
hyprctl workspaces
kanshictl status
grep -q closed /proc/acpi/button/lid/*/state && echo closed || echo open
```

Fix path:

- Ensure explicit close/open switch binds exist in Hyprland config.
- Verify `DP-1` is still the external connector name.
- Run `~/.config/hypr/scripts/lid.sh closed` manually while connected to `DP-1` to test the correction.
- After the manual correction, confirm `kanshictl status` reports a docked profile. If it still reports `laptop`, kanshi is fighting the lid correction.

Expected corrected state:

- `hyprctl monitors` shows `DP-1` and does not show enabled `eDP-1`.
- `hyprctl workspaces` shows workspace `1` and `2` on `DP-1`.
- `kanshictl status` shows `docked_dp_only` or `docked_dp_hdmi`.

## HDMI Presentation Does Not Mirror

Likely causes:

- Kanshi did not select the `mirror` profile.
- HDMI connector is not `HDMI-A-1`.
- The projector/TV does not accept `1920x1080@60Hz`.

Checks:

```bash
hyprctl monitors
kanshictl status
```

Fix path:

- Try preferred HDMI mode temporarily.
- Update `~/.config/kanshi/config` if the connector name changed.

## Audio Goes To The Wrong Device

Likely causes:

- Audio device appeared after the kanshi hook already ran.
- `kanshi-audio-route.service` is not running.
- Sink/source names changed after a PipeWire/WirePlumber update.

Checks:

```bash
systemctl --user status kanshi-audio-route.service
pactl list short sinks
pactl list short sources
pactl info
```

Fix path:

- Restart the watcher service.
- Re-run `~/.config/kanshi/audio-route.sh`.
- Update matching patterns in `audio-route.sh` only if sink/source names changed.
