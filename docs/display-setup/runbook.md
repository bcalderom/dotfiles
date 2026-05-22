# Runbook

Use this when checking or recovering the display setup.

## Inspect Current State

```bash
hyprctl monitors
hyprctl workspaces
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
kanshictl status
```

Expected result: only `DP-1` is enabled, workspace `1` and `2` are on `DP-1`, and kanshi reports `docked_dp_only` or `docked_dp_hdmi`.

Force open-lid correction:

```bash
~/.config/hypr/scripts/lid.sh open
```

If `eDP-1` does not remain enabled after `lid.sh open`, check `kanshictl status`; an active docked profile can keep the internal panel disabled.

## Check Lid Binds

```bash
hyprctl devices
hyprctl binds
```

Expected binds:

- `switch:on:Lid Switch` runs `~/.config/hypr/scripts/lid.sh closed`.
- `switch:off:Lid Switch` runs `~/.config/hypr/scripts/lid.sh open`.

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
bash -n ~/.config/kanshi/post-docked.sh ~/.config/kanshi/post-laptop.sh ~/.config/kanshi/post-mirror.sh ~/.config/kanshi/audio-route.sh ~/.config/kanshi/audio-route-watch.sh ~/.config/hypr/scripts/lid.sh
```

Then log out and log back in for full startup validation.
