# Config Map

This map defines one owner for every part of the setup. Do not add another automatic process that changes monitor rules.

## Hyprland Session

File: `~/.config/hypr/hyprland.lua`

Responsibilities:

- Define descriptor-based monitor defaults and the generic fallback.
- Start `hypridle`, Waybar, SwayNC, applications, and `hypr-lid.service`.
- Define workspace and application keybinds.
- Export `DE=generic` so `xdg-utils` does not probe an unavailable X server when identifying Hyprland.

Hyprland does not bind lid switch events directly. It also does not start `kanshi` or invoke `lid.sh` separately at startup.

## Transition Coordinator

Files:

- `~/.config/hypr/scripts/lid-watch.sh`
- `~/.config/hypr/scripts/lid.sh`
- `~/.config/systemd/user/hypr-lid.service`

`lid-watch.sh` responsibilities:

- Discover the active Hyprland instance when systemd lacks its environment.
- Poll lid state and the `DP-1`, `eDP-1`, and `HDMI-A-1` topology.
- Require four identical samples, separated by 0.5 seconds, before handling a changed topology.
- Reconcile stable states whose monitor or workspace arrangement is wrong.
- Record the last stable active workspace for unplug recovery.
- Retry failed stable states with capped backoff instead of marking them handled.

`lid.sh` responsibilities:

- Serialize transitions with a runtime lock.
- Apply runtime monitor and workspace rules through Hyprland's Lua IPC.
- Enable and verify the destination output before moving workspaces.
- Move and rebind existing workspaces while preserving focus.
- Save the internal-panel brightness and set its backlight to zero before disabling `eDP-1` when docked and closed.
- Disable `eDP-1` only after `DP-1` is active, workspace migration completes, and focus is restored.
- Restore the saved brightness after `eDP-1` is successfully enabled.
- Avoid modesetting outputs that are already active.
- Avoid routine DPMS toggles on `eDP-1`.
- Avoid automatic reload while `DP-1` remains usable; permit one delayed reload only when no usable output remains.
- Give `DP-1` priority over HDMI when both are connected.
- Configure HDMI mirroring when `DP-1` is absent.

The script still accepts `open` or `closed` for manual recovery and can read the lid state when called without an argument.

## Workspace Rules

- Lid closed with `DP-1`: active and occupied workspaces move to `DP-1`; nonpersistent rules `1-10` target `DP-1`; `eDP-1` is disabled.
- Lid open with `DP-1`: existing external workspaces stay on `DP-1`; the next numbered workspace targets `eDP-1`.
- Lid open without `DP-1`: active and occupied workspaces move to `eDP-1`; nonpersistent rules `1-10` target it for future use.
- All managed workspace rules use `persistent:false`.
- Empty inactive workspaces disappear; each enabled monitor still has one active workspace as required by Hyprland.
- Empty auto-created internal workspaces do not affect the docked-open workspace number and are demoted to `persistent:false`.

## Audio Routing

Files:

- `~/.config/kanshi/audio-route.sh`
- `~/.config/kanshi/audio-route-watch.sh`
- `~/.config/systemd/user/kanshi-audio-route.service`

These names are historical. The service watches PipeWire events and the transition handler runs the router after a stable display change. Neither configures displays or requires a running `kanshi` process.
