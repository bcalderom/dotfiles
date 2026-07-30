# Scenarios

## Docked Desktop

Trigger: `DP-1` connected and lid closed.

- `DP-1` is active at `2560x1440@120.01Hz`.
- HDMI is disabled when it is also connected.
- Protected workspaces and workspace rules move to `DP-1`.
- The active workspace is restored.
- `eDP-1` stays logically active as a hidden fallback output.
- The `intel_backlight` brightness is saved and set to zero.

Verify with:

```bash
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
hyprctl activeworkspace
```

## Docked Lid Open

Trigger: `DP-1` connected and lid open.

- `DP-1` and `eDP-1` are active.
- Existing non-empty `DP-1` workspaces remain there.
- `max(non-empty DP-1 workspace IDs) + 1` is placed on `eDP-1` with `persistent:false`.
- The previously active workspace remains active.
- The saved internal-panel brightness is restored.

## Laptop Only

Trigger: lid open with no external output.

- `eDP-1` is active at its preferred mode.
- Protected workspaces and rules `1` and `2` target `eDP-1`.
- Unplug recovery restores the last stable active workspace rather than an empty auto-created workspace.

The coordinator moves and restores workspaces `1`, `2`, the active workspace, and occupied workspaces. Only `1`, `2`, and occupied workspaces use `persistent:true`; workspace `3` and other empty workspaces use `persistent:false`.

Closing the lid without an external monitor does not create a display transition; normal suspend or lock policy remains responsible.

## HDMI Mirror

Trigger: lid open with `HDMI-A-1` connected and `DP-1` absent.

- `eDP-1` is enabled first and remains the workspace-bearing output.
- `HDMI-A-1` uses `1920x1080@60Hz` and mirrors `eDP-1`.
- Existing workspaces and focus remain on `eDP-1`.

## Connector Flap

Trigger: an output appears or disappears for fewer than four stable samples.

- The coordinator does not run a display transition for the transient state.
- Applications, workspaces, and focus remain untouched.
- Once one topology remains stable, exactly one reconciliation runs.

## Startup Apps

- Browser starts on workspace `1`.
- Terminal starts on workspace `2`.
- Application placement does not control monitor or lid behavior.
