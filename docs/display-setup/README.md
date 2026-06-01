# Display Setup

This directory documents the laptop display, workspace, lid, and audio behavior for the Lenovo/Hyprland setup.

Hyprland calls desktops `workspaces`; this documentation uses `workspace` for config accuracy and mentions `desktop` only when describing the user-facing behavior.

## Goals

- Use the laptop alone when mobile.
- Use the external USB-C monitor as the only display when docked with the lid closed.
- Mirror the laptop display over HDMI for meetings and presentations.
- Keep monitor layout, workspace placement, lid handling, and audio routing understandable after package updates.

## Ownership Model

- `kanshi` owns display profile selection: docked, laptop-only, and HDMI mirror.
- Hyprland owns compositor behavior: workspaces, startup apps, keybinds, and lid switch binding.
- `~/.config/hypr/scripts/lid.sh` owns the lid-closed invariant: when `DP-1` exists and the lid is closed, kanshi must be on a docked profile and workspace `1` and `2` must be on `DP-1` before `eDP-1` is disabled.
- The kanshi post-profile scripts bridge profile changes into Hyprland workspace moves and audio routing.
- The audio watcher service re-runs routing when PipeWire devices appear or disappear.

## Critical Invariants

- Docked lid-closed mode must end with only `DP-1` enabled.
- Docked lid-closed mode must end with workspaces `1` and `2` on `DP-1`.
- `kanshictl status` must report `docked_dp_only` or `docked_dp_hdmi` while the lid is closed on the USB-C monitor.
- Docked lid-open mode must switch to `docked_open_dp_only` or `docked_open_dp_hdmi` so `eDP-1` stays powered while `DP-1` remains connected.
- Docked lid-open mode must place workspace `1` on `DP-1` and workspace `2` on `eDP-1`.
- Laptop recovery after unplug must end with `eDP-1` enabled, DPMS on, and workspaces moved back to `eDP-1`.
- `kanshictl status` must report `laptop` after the USB-C monitor is unplugged.
- App startup placement must not be used to fix monitor or lid behavior.

## Files

- `hardware-and-identifiers.md`: monitor connectors and descriptor strings.
- `scenarios.md`: expected behavior for each real-world setup.
- `config-map.md`: config files and responsibility boundaries.
- `runbook.md`: commands for checking, reloading, and recovering the setup.
- `troubleshooting.md`: symptom-based checks and likely fixes.
- `update-checklist.md`: quick checks after Arch package updates.

## Startup Placement

Browser and terminal startup uses native Hyprland workspace-targeted `exec-once` rules:

- Browser starts on workspace `1`.
- Terminal starts on workspace `2`.

Monitor profile selection remains owned by kanshi; lid-closed correction remains owned by the lid script.

## Last Validated Behavior

The closed-lid correction was validated manually with:

```bash
~/.config/hypr/scripts/lid.sh closed
hyprctl monitors
hyprctl workspaces
kanshictl status
```

Expected result: `eDP-1` is disabled, workspaces `1` and `2` are on `DP-1`, and kanshi reports a docked profile.

The docked lid-open path is validated with:

```bash
~/.config/hypr/scripts/lid.sh open
hyprctl monitors
hyprctl workspaces
kanshictl status
```

Expected result while `DP-1` is connected: `eDP-1` and `DP-1` are both enabled, `eDP-1` has DPMS on, workspace `1` is on `DP-1`, workspace `2` is on `eDP-1`, and kanshi reports a docked-open profile.

The unplug/open recovery path is validated with:

```bash
~/.config/hypr/scripts/lid.sh open
hyprctl monitors
hyprctl workspaces
kanshictl status
```

Expected result: `eDP-1` is enabled with DPMS on, workspaces are on `eDP-1`, and kanshi reports `laptop` when `DP-1` is absent.
