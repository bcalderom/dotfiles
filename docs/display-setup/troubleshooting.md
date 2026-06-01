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
hyprctl binds
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
kanshictl status
systemctl --user status hypr-lid.path hypr-lid.service
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
- `hyprctl workspacerules` shows workspace `1` and `2` bound to `DP-1`.
- `kanshictl status` shows `docked_dp_only` or `docked_dp_hdmi`.

## Laptop Screen Black After Unplug

Likely causes:

- The lid open event fired before `DP-1` disappeared, so the laptop profile was not selected yet.
- Kanshi switched to `laptop`, but `eDP-1` DPMS stayed off.
- Workspaces remained logically available, but focus did not move cleanly back to `eDP-1`.

Checks:

```bash
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
kanshictl status
grep -q closed /proc/acpi/button/lid/*/state && echo closed || echo open
```

Fix path:

- Run `~/.config/hypr/scripts/lid.sh open` after unplugging from `DP-1`.
- If that works, the issue is the unplug/open race and `post-laptop.sh` should be checked because it owns profile-triggered recovery.

Expected corrected state:

- `hyprctl monitors` shows enabled `eDP-1` with `dpmsStatus: 1`.
- `hyprctl workspaces` shows workspace `1` and `2` on `eDP-1`.
- `hyprctl workspacerules` shows workspace `1` and `2` bound to `eDP-1`.
- `kanshictl status` shows `laptop`.

## Laptop Screen Black While Still Docked

Likely causes:

- Kanshi stayed on `docked_dp_only` or `docked_dp_hdmi`, which intentionally disables `eDP-1`.
- The lid-open event did not switch to a docked-open profile.

Checks:

```bash
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
kanshictl status
grep -q closed /proc/acpi/button/lid/*/state && echo closed || echo open
```

Fix path:

- Run `~/.config/hypr/scripts/lid.sh open` while `DP-1` is connected.
- Confirm `kanshictl status` changes to `docked_open_dp_only` or `docked_open_dp_hdmi`.

Expected corrected state:

- `hyprctl monitors` shows enabled `DP-1` and `eDP-1`.
- `hyprctl monitors` shows `dpmsStatus: 1` for `eDP-1`.
- `hyprctl workspaces` shows workspace `1` on `DP-1` and workspace `2` on `eDP-1`.
- `hyprctl workspacerules` shows workspace `1` bound to `DP-1` and workspace `2` bound to `eDP-1`.
- `kanshictl status` shows `docked_open_dp_only` or `docked_open_dp_hdmi`.

If an extra empty workspace appears on `eDP-1`, rerun `~/.config/hypr/scripts/lid.sh open`; the handler should make workspace `2` active on `eDP-1` and remove Hyprland's temporary empty workspace.

If `hyprctl workspaces` and `hyprctl workspacerules` are correct but Waybar still shows stale workspace buttons, restart Waybar with `SUPER+W`. The lid and kanshi transition hooks already ask Hyprland to restart Waybar after docked, docked-open, and laptop transitions when Waybar is running.

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
