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

- Docked lid-closed mode temporarily blanks the internal panel, disables `eDP-1` after workspace migration, and restores its saved brightness for the next console or boot.
- Active and occupied workspaces move to `DP-1` before `eDP-1` is disabled.
- Nonpersistent workspace rules `1-10` follow the primary display; docked-open mode overrides only its designated internal workspace.
- Docked lid-open mode keeps existing `DP-1` workspaces there and creates the next numbered workspace on `eDP-1`.
- The docked-open workspace is `max(non-empty DP-1 workspace IDs) + 1` and is non-persistent.
- All workspace rules are non-persistent, so empty inactive workspaces disappear.
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
