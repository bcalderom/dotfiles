# Display Setup

This directory documents display, workspace, lid, and audio behavior for the Lenovo/Hyprland setup.

## Goals

- Use the laptop alone when mobile.
- Use the USB-C monitor as the only display when docked with the lid closed.
- Use both displays when docked with the lid open.
- Mirror the laptop display over HDMI for presentations.
- Preserve running applications, workspace placement, and focus across transitions.

## Ownership Model

- Hyprland owns output configuration and workspace behavior.
- `hypr-lid.service` is the only automatic display-transition coordinator.
- `lid-watch.sh` waits for a stable lid/output topology before calling `lid.sh`.
- `lid.sh` enables the destination output, moves workspaces, then disables an old output when required.
- `kanshi` is not started and no display profile hooks are used.
- The separately managed `kanshi-audio-route.service` retains its historical name but only routes audio.

## Critical Invariants

- Docked lid-closed mode ends with only `DP-1` enabled.
- Workspaces move to an active destination before `eDP-1` is disabled.
- Workspace rules for `1`, `2`, and `3` follow the single active display.
- Docked lid-open mode keeps existing `DP-1` workspaces there and creates the next numbered workspace on `eDP-1`.
- The docked-open workspace is `max(non-empty DP-1 workspace IDs) + 1` and is non-persistent.
- The previously active workspace is restored after every transition.
- HDMI mirror mode keeps `eDP-1` as the source and mirrors it to `HDMI-A-1`.
- No transition restarts Waybar or another user application.

## Files

- `hardware-and-identifiers.md`: connectors and descriptor strings.
- `scenarios.md`: expected behavior for each physical setup.
- `config-map.md`: configuration ownership boundaries.
- `runbook.md`: inspection, recovery, and validation commands.
- `troubleshooting.md`: symptom-based diagnosis.
- `update-checklist.md`: checks after system updates.

## Startup Placement

Hyprland starts the browser on workspace `1` and the terminal on workspace `2` with workspace-targeted `exec-once` rules. Application startup placement is independent from display transitions.

## Validation

```bash
systemctl --user status hypr-lid.service
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
hyprctl activeworkspace
```

The active monitor arrangement and workspace rules should match the scenarios documented in `scenarios.md`.
