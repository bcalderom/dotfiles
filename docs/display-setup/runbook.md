# Runbook

Use this when checking or recovering the display setup.

## Inspect Current State

```bash
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
hyprctl activeworkspace
kanshictl status
pactl info
```

## Reload Display Profiles

```bash
kanshictl reload
```

If `kanshictl` is unavailable, restart kanshi from the Hyprland session.

```bash
pkill kanshi
kanshi &
```

## Re-run Profile Hooks Manually

Docked:

```bash
~/.config/kanshi/post-docked.sh
```

Laptop-only:

```bash
~/.config/kanshi/post-laptop.sh
```

HDMI mirror:

```bash
~/.config/kanshi/post-mirror.sh
```

## Re-run Lid Handling

Auto-detect current lid state:

```bash
~/.config/hypr/scripts/lid.sh
```

Force closed-lid correction:

```bash
~/.config/hypr/scripts/lid.sh closed
```

Validate closed-lid correction:

```bash
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
kanshictl status
```

Expected result: only `DP-1` is enabled, workspaces `1`, `2`, and `3` are on `DP-1`, workspace rules bind those workspaces to `DP-1`, the previously active workspace remains active, and kanshi reports `docked_dp_only` or `docked_dp_hdmi`.

Force open-lid correction:

```bash
~/.config/hypr/scripts/lid.sh open
```

Validate docked open-lid correction:

```bash
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
kanshictl status
```

Expected result when `DP-1` is present: both `DP-1` and `eDP-1` are enabled, `eDP-1` has `dpmsStatus: 1`, workspaces `1` and `2` are on `DP-1`, persistent workspace `3` is on `eDP-1`, workspace rules match that split, the previously active workspace remains active, and kanshi reports `docked_open_dp_only` or `docked_open_dp_hdmi`.

Validate open-lid/unplug correction:

```bash
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
kanshictl status
```

Expected result when `DP-1` and HDMI are absent: `eDP-1` is enabled with `dpmsStatus: 1`, workspaces `1`, `2`, and `3` are on `eDP-1`, workspace rules bind those workspaces to `eDP-1`, the previously active workspace remains active, and kanshi reports `laptop`.

Expected result when `DP-1` is absent and HDMI is present: `eDP-1` is enabled with `dpmsStatus: 1`, `HDMI-A-1` mirrors `eDP-1`, workspaces remain on `eDP-1`, and kanshi reports `mirror`.

If `eDP-1` does not remain enabled after `lid.sh open`, check `kanshictl status`; it should not remain on `docked_dp_only` or `docked_dp_hdmi` after opening the lid.

## Check Lid Binds

```bash
hyprctl devices
hyprctl binds
```

Expected binds:

- `switch:on:Lid Switch` runs `~/.config/hypr/scripts/lid.sh closed`.
- `switch:off:Lid Switch` runs `~/.config/hypr/scripts/lid.sh open`.
- The script still reads `/proc/acpi/button/lid/LID0/state` when called without an explicit state.

Check the backup systemd watcher:

```bash
systemctl --user status hypr-lid.service
systemd-analyze --user verify ~/.config/systemd/user/hypr-lid.service
systemctl --user show-environment | grep -E 'HYPRLAND_INSTANCE_SIGNATURE|WAYLAND_DISPLAY'
```

## Re-run Audio Routing

```bash
~/.config/kanshi/audio-route.sh
```

Restart the watcher:

```bash
systemctl --user restart kanshi-audio-route.service
systemctl --user status kanshi-audio-route.service
```

## Check Startup Placement

```bash
hyprctl clients
hyprctl workspaces
```

If browser or terminal appears on the wrong workspace after login, inspect the Hyprland `exec-once = [workspace ... silent]` rules and check whether the app restored an existing session/window.

## After Editing Configs

Syntax-check shell hooks:

```bash
bash -n ~/.config/kanshi/post-docked.sh ~/.config/kanshi/post-docked-open.sh ~/.config/kanshi/post-laptop.sh ~/.config/kanshi/post-mirror.sh ~/.config/kanshi/audio-route.sh ~/.config/kanshi/audio-route-watch.sh ~/.config/hypr/scripts/lid.sh ~/.config/hypr/scripts/lid-watch.sh
```

Then log out and log back in for full startup validation.
