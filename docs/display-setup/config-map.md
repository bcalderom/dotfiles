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
- `docked_open_dp_hdmi`: internal and dock monitor enabled, HDMI disabled.
- `docked_open_dp_only`: internal and dock monitor enabled.
- `mirror`: internal enabled and HDMI mirrored.
- `laptop`: internal display only.

## Post-Profile Hooks

Files:

- `~/.config/kanshi/post-docked.sh`
- `~/.config/kanshi/post-laptop.sh`
- `~/.config/kanshi/post-mirror.sh`

Responsibilities:

- Wait briefly for Hyprland to expose the expected monitor.
- Set Hyprland workspace monitor rules and move workspaces `1`, `2`, `3`, and the active workspace to the expected monitor for docked, laptop, and mirror modes.
- Force `eDP-1` and DPMS on in laptop mode to recover after unplugging from docked mode.
- Apply mirror-specific Hyprland monitor keywords.
- Re-run audio routing after the display profile changes.
- Restart Waybar through Hyprland after docked, docked-open, and laptop display transitions when Waybar is already running.

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
- `exec-once = bash -lc 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP; systemctl --user restart hypr-lid.service'`
- `exec-once = [workspace 1 silent] $browser`
- `exec-once = [workspace 2 silent] $terminal`
- `bindl = ,switch:on:Lid Switch,exec,~/.config/hypr/scripts/lid.sh closed`
- `bindl = ,switch:off:Lid Switch,exec,~/.config/hypr/scripts/lid.sh open`

## Lid Handling

Files:

- `~/.config/hypr/scripts/lid.sh`
- `~/.config/hypr/scripts/lid-watch.sh`
- `~/.config/systemd/user/hypr-lid.service`

Responsibilities:

- Run once at startup to handle sessions that start with the lid already closed.
- Accept explicit `open`/`closed` arguments from Hyprland switch binds and the watcher; fall back to reading the lid state when called without arguments.
- Run a user service watcher that polls lid state and `DP-1`/`eDP-1`/`HDMI-A-1` topology, then calls `lid.sh` when either changes.
- If lid closes and `DP-1` exists, switch kanshi to a docked profile, bind/move workspaces `1`, `2`, `3`, and the active workspace to `DP-1`, disable `eDP-1`, then restore the previously active workspace.
- If lid opens and `DP-1` is still present, switch kanshi to a docked-open profile, request `eDP-1` with preferred mode, force DPMS on, keep workspaces `1` and `2` on `DP-1`, keep persistent workspace `3` on `eDP-1`, and restore the previously active workspace.
- If lid opens and `DP-1` is absent but `HDMI-A-1` is present, switch kanshi to `mirror`, keep `eDP-1` as the master output, mirror it to HDMI, move workspaces to `eDP-1`, and restore the previously active workspace.
- If lid opens and no external display is present, switch kanshi to `laptop`, request `eDP-1` with preferred mode, force DPMS on, bind/move workspaces `1`, `2`, `3`, and the active workspace to `eDP-1`, and restore the previously active workspace.

Implementation details:

- `lid.sh closed` first tries `kanshictl switch docked_dp_hdmi`.
- If that does not match the current output set, it falls back to `kanshictl switch docked_dp_only`.
- This prevents kanshi from staying on `laptop` and immediately re-enabling `eDP-1` after Hyprland disables it.
- `lid.sh open` switches to `docked_open_dp_hdmi` or `docked_open_dp_only` while `DP-1` is still present.
- `lid.sh open` gives `DP-1` priority over HDMI when both are connected, matching the kanshi docked profiles that disable HDMI in docked mode.
- In docked-open mode, workspace `3` is persistent on `eDP-1`; focus is not forced to it.
- `lid.sh open` switches to `mirror` when `DP-1` is absent and `HDMI-A-1` is connected.
- `lid.sh open` switches to `laptop` only when `DP-1` and `HDMI-A-1` are absent.
- The `hyprctl keyword workspace "N,monitor:OUTPUT"` rules are updated during each transition so later manual workspace switches stay on the intended display.

Known cleanup:

- `~/.config/systemd/user/hypr-lid.service` runs `lid-watch.sh` as a backup to Hyprland switch binds because path watching `/proc/acpi/button/lid/LID0/state` is not reliable after system updates.
- `lid-watch.sh` also watches monitor topology so USB-C connect/disconnect events reconcile workspace rules even when the lid state does not change.
- `lid-watch.sh` reconciles stable invalid states too, such as a closed lid with `eDP-1` still active or workspace rules pointing at the wrong output.
- `lid-watch.sh` discovers the active Hyprland instance with `hyprctl instances` if systemd starts it without `HYPRLAND_INSTANCE_SIGNATURE` or `WAYLAND_DISPLAY`.

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
