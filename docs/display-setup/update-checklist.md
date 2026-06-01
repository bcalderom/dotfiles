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
hyprctl workspacerules
hyprctl activeworkspace
```

Check audio:

```bash
systemctl --user status kanshi-audio-route.service
pactl info
```

## Scenario Smoke Tests

- Laptop-only: disconnect external displays, reload kanshi, confirm `eDP-1` is enabled, DPMS is on, workspaces `1` and `2` are on it, workspace rules bind them to `eDP-1`, and `kanshictl status` reports `laptop`.
- Docked: connect USB-C monitor, close lid, confirm `DP-1` is enabled, `eDP-1` is disabled, workspaces `1` and `2` are on `DP-1`, workspace rules bind them to `DP-1`, and `kanshictl status` reports a docked profile.
- Docked lid-open: while USB-C monitor is still connected, open the lid and confirm both `DP-1` and `eDP-1` are enabled, workspace `1` is on `DP-1`, workspace `2` is on `eDP-1`, workspace rules match that split, and `kanshictl status` reports a docked-open profile.
- Unplug recovery: from docked mode, unplug USB-C, open the lid, confirm `eDP-1` is enabled, DPMS is on, and workspaces return to `eDP-1`.
- HDMI mirror: connect HDMI output without dock mode, confirm `HDMI-A-1` mirrors `eDP-1`.
- Startup apps: confirm browser is on workspace `1` and terminal is on workspace `2`.

## Manual Docked Recovery

If docked state is wrong after login or package updates:

```bash
~/.config/hypr/scripts/lid.sh closed
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
kanshictl status
```

Expected result: only `DP-1` is enabled, workspace `1` and `2` are on `DP-1`, workspace rules bind both workspaces to `DP-1`, and kanshi reports `docked_dp_only` or `docked_dp_hdmi`.

## Manual Docked-Open Recovery

If the laptop screen stays black while the external USB-C monitor is still connected:

```bash
~/.config/hypr/scripts/lid.sh open
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
kanshictl status
```

Expected result: both `DP-1` and `eDP-1` are enabled, `eDP-1` has DPMS on, workspace `1` is on `DP-1`, workspace `2` is on `eDP-1`, workspace rules match that split, and kanshi reports `docked_open_dp_only` or `docked_open_dp_hdmi`.

## Manual Laptop Recovery

If the laptop screen stays black after unplugging the external monitor:

```bash
~/.config/hypr/scripts/lid.sh open
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
kanshictl status
```

Expected result: `eDP-1` is enabled with DPMS on, workspace `1` and `2` are on `eDP-1`, workspace rules bind both workspaces to `eDP-1`, and kanshi reports `laptop`.

## If Something Regressed

Collect this output before changing config:

```bash
hyprctl monitors
hyprctl workspaces
hyprctl clients
hyprctl workspacerules
kanshictl status
pactl list short sinks
pactl list short sources
systemctl --user status kanshi-audio-route.service
```

Then compare the live monitor and audio identifiers against `hardware-and-identifiers.md`.
