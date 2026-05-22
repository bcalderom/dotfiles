# Config Map

This map defines which file owns each part of the setup. Keep responsibilities separated to avoid update-sensitive races.

## Display Profiles

File: `~/.config/kanshi/config`

Responsibilities:

- Detect laptop-only, docked USB-C, and HDMI mirror scenarios.
- Enable, disable, position, and set modes for outputs.
- Run the matching post-profile hook.

Profiles:

- `docked_dp_hdmi`: dock monitor enabled, internal disabled, HDMI disabled.
- `docked_dp_only`: dock monitor enabled, internal disabled.
- `mirror`: internal enabled and HDMI mirrored.
- `laptop`: internal display only.

## Post-Profile Hooks

Files:

- `~/.config/kanshi/post-docked.sh`
- `~/.config/kanshi/post-laptop.sh`
- `~/.config/kanshi/post-mirror.sh`

Responsibilities:

- Wait briefly for Hyprland to expose the expected monitor.
- Move workspace `1` and `2` to the expected monitor for docked/laptop modes.
- Apply mirror-specific Hyprland monitor keywords.
- Re-run audio routing after the display profile changes.

## Hyprland Session

File: `~/.config/hypr/hyprland.conf`

Responsibilities:

- Define monitor fallback rules.
- Start `kanshi`, `hypridle`, `waybar`, `swaync`, and current app autostart.
- Define workspace and app keybinds.
- Bind lid switch events to the lid script.

Important lines:

- `exec-once = kanshi`
- `exec-once = ~/.config/hypr/scripts/lid.sh`
- `exec-once = [workspace 1 silent] $browser`
- `exec-once = [workspace 2 silent] $terminal`
- `bindl = ,switch:on:Lid Switch,exec,~/.config/hypr/scripts/lid.sh closed`
- `bindl = ,switch:off:Lid Switch,exec,~/.config/hypr/scripts/lid.sh open`

## Lid Handling

File: `~/.config/hypr/scripts/lid.sh`

Responsibilities:

- Run once at startup to handle sessions that start with the lid already closed.
- If lid closes and `DP-1` exists, switch kanshi to a docked profile, move workspace `1`, workspace `2`, and the active workspace to `DP-1`, then disable `eDP-1`.
- If lid opens, request `eDP-1` with preferred mode. The active kanshi profile may still keep `eDP-1` disabled while docked.

Implementation details:

- `lid.sh closed` first tries `kanshictl switch docked_dp_hdmi`.
- If that does not match the current output set, it falls back to `kanshictl switch docked_dp_only`.
- This prevents kanshi from staying on `laptop` and immediately re-enabling `eDP-1` after Hyprland disables it.

Known cleanup:

- `~/.config/systemd/user/hypr-lid.service` currently points to `lid-handler.sh`, which is not present. Prefer one lid mechanism and remove or fix stale units later.

## Audio Routing

Files:

- `~/.config/kanshi/audio-route.sh`
- `~/.config/kanshi/audio-route-watch.sh`
- `~/.config/systemd/user/kanshi-audio-route.service`

Responsibilities:

- Choose default sink/source after monitor and device changes.
- Prefer USB/Bluetooth audio devices.
- Prefer HDMI audio when docked on `DP-1` and no better external device exists.
- Fall back to internal speaker/headphones and internal microphone.
