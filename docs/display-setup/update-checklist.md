# Update Checklist

Run this after Arch package updates, especially after Hyprland, kanshi, PipeWire, WirePlumber, kernel, or graphics stack updates.

## Before Reboot

```bash
git status --short
```

Confirm local dotfile changes are committed or intentionally left untracked.

## After Login

Check the active outputs:

```bash
hyprctl monitors
kanshictl status
```

Check workspaces:

```bash
hyprctl workspaces
hyprctl activeworkspace
```

Check audio:

```bash
systemctl --user status kanshi-audio-route.service
pactl info
```

## Scenario Smoke Tests

- Laptop-only: disconnect external displays, reload kanshi, confirm `eDP-1` is enabled and workspaces `1` and `2` are on it.
- Docked: connect USB-C monitor, close lid, confirm `DP-1` is enabled, `eDP-1` is disabled, workspaces `1` and `2` are on `DP-1`, and `kanshictl status` reports a docked profile.
- HDMI mirror: connect HDMI output without dock mode, confirm `HDMI-A-1` mirrors `eDP-1`.
- Startup apps: confirm browser is on workspace `1` and terminal is on workspace `2`.

## Manual Docked Recovery

If docked state is wrong after login or package updates:

```bash
~/.config/hypr/scripts/lid.sh closed
hyprctl monitors
hyprctl workspaces
kanshictl status
```

Expected result: only `DP-1` is enabled, workspace `1` and `2` are on `DP-1`, and kanshi reports `docked_dp_only` or `docked_dp_hdmi`.

## If Something Regressed

Collect this output before changing config:

```bash
hyprctl monitors
hyprctl workspaces
hyprctl clients
kanshictl status
pactl list short sinks
pactl list short sources
systemctl --user status kanshi-audio-route.service
```

Then compare the live monitor and audio identifiers against `hardware-and-identifiers.md`.
