# Config Map

This map defines one owner for every part of the setup. Do not add another automatic process that calls `hyprctl keyword monitor`.

## Hyprland Session

File: `~/.config/hypr/hyprland.conf`

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

`lid.sh` responsibilities:

- Serialize transitions with a runtime lock.
- Enable and verify the destination output before moving workspaces.
- Move and rebind existing workspaces while preserving focus.
- Disable `eDP-1` only after `DP-1` is active and workspace moves are complete.
- Avoid modesetting outputs that are already active.
- Give `DP-1` priority over HDMI when both are connected.
- Configure HDMI mirroring when `DP-1` is absent.

The script still accepts `open` or `closed` for manual recovery and can read the lid state when called without an argument.

## Workspace Rules

- Lid closed with `DP-1`: all existing workspaces move to `DP-1`; rules `1`, `2`, and `3` target `DP-1`.
- Lid open with `DP-1`: existing external workspaces stay on `DP-1`; the next numbered workspace targets `eDP-1`.
- Lid open without `DP-1`: all existing workspaces and rules `1`, `2`, and `3` target `eDP-1`.
- Empty auto-created internal workspaces do not affect the docked-open workspace number.

## Audio Routing

Files:

- `~/.config/kanshi/audio-route.sh`
- `~/.config/kanshi/audio-route-watch.sh`
- `~/.config/systemd/user/kanshi-audio-route.service`

These names are historical. The service watches PipeWire events and the transition handler runs the router after a stable display change. Neither configures displays or requires a running `kanshi` process.
