# Scenarios

Each scenario lists the trigger, selected profile, expected monitor state, expected workspaces, expected audio behavior, and quick verification commands.

## Docked Desktop

Use this when working at the desk with the USB-C external monitor and the laptop lid closed.

| Item | Expected behavior |
| --- | --- |
| Trigger | USB-C external monitor connected; optional HDMI connected but not used |
| Kanshi profile | `docked_dp_only` or `docked_dp_hdmi` |
| Internal display | Disabled |
| External display | `DP-1` enabled at `2560x1440@120.01Hz` |
| HDMI display | Disabled in `docked_dp_hdmi` |
| Workspaces | Workspace `1` and `2` moved to `DP-1` |
| Lid close | Switches kanshi to a docked profile, moves workspace `1` and `2` to `DP-1`, then disables `eDP-1` |
| Audio | Prefer external USB/Bluetooth sink; otherwise HDMI sink when `DP-1` is active |

Verification:

```bash
hyprctl monitors
hyprctl workspaces
kanshictl status
systemctl --user status kanshi-audio-route.service
```

Expected docked validation:

- `hyprctl monitors` shows `DP-1` only.
- `hyprctl workspaces` shows workspace `1` and `2` on `DP-1`.
- `kanshictl status` shows `docked_dp_only` or `docked_dp_hdmi`.

## Laptop Only

Use this in mobile/cafe mode with no external monitor.

| Item | Expected behavior |
| --- | --- |
| Trigger | No USB-C dock monitor and no HDMI output |
| Kanshi profile | `laptop` |
| Internal display | `eDP-1` enabled at preferred mode |
| External display | Disabled/not present |
| HDMI display | Disabled/not present |
| Workspaces | Workspace `1` and `2` moved to `eDP-1` |
| Lid close | Normally suspends/locks according to system policy if no external monitor is available |
| Audio | Prefer external USB/Bluetooth device; otherwise internal speaker/headphones |

Verification:

```bash
hyprctl monitors
hyprctl workspaces
kanshictl status
pactl info
```

Expected laptop validation:

- `hyprctl monitors` shows `eDP-1` enabled.
- `kanshictl status` shows `laptop`.

## HDMI Mirror Presentation

Use this for meetings and presentations where the laptop display should be mirrored to HDMI.

| Item | Expected behavior |
| --- | --- |
| Trigger | HDMI display connected without the USB-C docked monitor profile taking precedence |
| Kanshi profile | `mirror` |
| Internal display | `eDP-1` enabled at preferred mode at `0x0` |
| HDMI display | `HDMI-A-1` enabled at `1920x1080@60Hz`, mirrored from `eDP-1` |
| Workspaces | Remain on the mirrored laptop display |
| Lid close | Not the primary presentation use case; keep lid open while presenting |
| Audio | Prefer external USB/Bluetooth device; otherwise internal speaker/headphones or available HDMI sink |

Verification:

```bash
hyprctl monitors
kanshictl status
```

## Startup Apps

Current behavior:

- Browser starts on workspace `1` via Hyprland `exec-once`.
- Terminal starts on workspace `2` via Hyprland `exec-once`.
- App placement does not switch the active workspace during startup.
- Lid and monitor behavior must still be correct if either app starts slowly or restores an existing session.

Design constraint:

- Keep monitor/lid behavior independent from app startup placement.
