# Troubleshooting

## Repeated Display Changes Or Client Crashes

Likely causes:

- Another process is configuring outputs.
- The connector is flapping longer than the debounce window.
- A previous Hyprland session left stale user services running.

Checks:

```bash
systemctl --user status hypr-lid.service
journalctl --user -u hypr-lid.service -b
pgrep -a kanshi || true
hyprctl binds
coredumpctl list --since today
```

Only `hypr-lid.service` should automatically invoke display transitions. Stop any `kanshi` process and remove direct lid handlers before retesting.

## Docked Monitor Does Not Activate

```bash
hyprctl monitors
hyprctl monitors all
systemctl --user status hypr-lid.service
```

- Confirm the connector is still named `DP-1`.
- Compare the live descriptor with `hardware-and-identifiers.md`.
- Run `~/.config/hypr/scripts/lid.sh closed` manually.
- Check the service journal for unstable alternating topology entries.

## Lid Closed And Internal Display Stays Enabled

```bash
grep -q closed /proc/acpi/button/lid/*/state && echo closed || echo open
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
journalctl --user -u hypr-lid.service -b
```

The coordinator intentionally keeps `eDP-1` logically enabled when docked and closed. This avoids the upstream Aquamarine/i915 failure path where a disabled internal panel cannot reliably be re-enabled after `DP-1` disappears. Its `intel_backlight` brightness should be zero while closed.

Verify the physical backlight state with:

```bash
cat /sys/class/backlight/intel_backlight/actual_brightness
```

## Laptop Screen Black After Unplug

```bash
~/.config/hypr/scripts/lid.sh open
hyprctl monitors
hyprctl workspaces
hyprctl activeworkspace
```

Expected: `eDP-1` is active and the last stable active workspace is restored. Confirm `hypr-lid.service` is running so future topology changes reconcile automatically.

If `eDP-1` is still inactive, inspect the service journal. The coordinator allows one delayed `hyprctl reload` per stable topology, then backs off instead of repeatedly triggering live modesets.

## Laptop Screen Black While Docked

Run:

```bash
~/.config/hypr/scripts/lid.sh open
```

Expected: both `DP-1` and `eDP-1` are active, existing external workspaces stay on `DP-1`, and the next numbered workspace is on `eDP-1`.

## HDMI Does Not Mirror

```bash
hyprctl monitors all
~/.config/hypr/scripts/lid.sh open
```

- Confirm HDMI is named `HDMI-A-1`.
- Confirm `DP-1` is absent; it takes priority over HDMI.
- Verify the display accepts `1920x1080@60Hz`.

## Waybar Shows Stale Workspaces

Display transitions no longer restart Waybar. If Hyprland state is correct but Waybar is stale, restart it manually with `SUPER+W` and inspect Waybar logs separately.

## Chromium Or Electron App Does Not Open

If an application process exists but `hyprctl clients` has no matching window, check for blocked desktop-handler detection:

```bash
ps -C xdg-settings,xprop -o pid,ppid,etime,stat,args
ps -C Xwayland -o pid,ppid,etime,stat,args
```

`xdg-utils` does not identify Hyprland directly and can fall back to `xprop`. The Hyprland session exports `DE=generic` so these checks use the freedesktop MIME configuration without requiring Xwayland. Processes launched before that environment was applied must be restarted.

## Audio Goes To The Wrong Device

```bash
systemctl --user status kanshi-audio-route.service
pactl list short sinks
pactl list short sources
~/.config/kanshi/audio-route.sh
```

The audio service name and directory are historical; neither should configure displays.
