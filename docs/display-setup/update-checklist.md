# Update Checklist

Run this after Hyprland, kernel, graphics stack, PipeWire, or WirePlumber updates.

## After Login

```bash
systemctl --user status hypr-lid.service
journalctl --user -u hypr-lid.service -b
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
hyprctl activeworkspace
pgrep -a kanshi || true
```

Confirm the coordinator is active and no `kanshi` process is running.

## Scenario Smoke Tests

- Laptop-only: disconnect external displays and confirm `eDP-1` is enabled.
- Docked: connect `DP-1`, close the lid, and confirm active and occupied workspaces move while empty inactive workspaces disappear and `eDP-1` becomes disabled.
- Docked lid-open: open the lid and confirm both displays are enabled with the next numbered workspace on `eDP-1`.
- Unplug recovery: unplug `DP-1` and confirm workspaces and focus return to `eDP-1`.
- HDMI mirror: connect HDMI without `DP-1` and confirm it mirrors `eDP-1`.
- Startup applications: confirm browser is on workspace `1` and terminal is on workspace `2`.

## Automated Checks

```bash
bash scripts/desktop/hypr-lid-deploy/tests/test-lid.sh
bash scripts/desktop/hypr-lid-deploy/tests/test-lid-watch.sh
bash scripts/desktop/hypr-lid-deploy/tests/test-deploy.sh
```

## Audio

```bash
systemctl --user status kanshi-audio-route.service
pactl info
```

The audio service keeps its historical name and is independent of display configuration.

## Regression Evidence

Collect this before changing configuration:

```bash
journalctl --user -u hypr-lid.service -b
journalctl -b | grep -E 'Hyprland|aquamarine|wayland|drm'
coredumpctl list --since today
hyprctl monitors
hyprctl workspaces
hyprctl clients
hyprctl workspacerules
```
