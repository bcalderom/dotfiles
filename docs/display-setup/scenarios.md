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
hyprctl workspacerules
kanshictl status
systemctl --user status kanshi-audio-route.service
```

Expected docked validation:

- `hyprctl monitors` shows `DP-1` only.
- `hyprctl workspaces` shows workspace `1` and `2` on `DP-1`.
- `hyprctl workspacerules` shows workspace `1` and `2` bound to `DP-1`.
- `kanshictl status` shows `docked_dp_only` or `docked_dp_hdmi`.

## Docked Lid Open

Use this while still connected to the USB-C external monitor but with the laptop lid open.

| Item | Expected behavior |
| --- | --- |
| Trigger | USB-C external monitor connected and lid opened |
| Kanshi profile | `docked_open_dp_only` or `docked_open_dp_hdmi` |
| Internal display | `eDP-1` enabled at preferred mode with DPMS on |
| External display | `DP-1` remains enabled at `2560x1440@120.01Hz` |
| Workspaces | Workspace `1` on `DP-1`; workspace `2` on `eDP-1`; focus falls back to workspace `2` if Hyprland creates a temporary empty workspace |
| Audio | Prefer external USB/Bluetooth sink; otherwise HDMI sink when `DP-1` is active |

Verification:

```bash
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
kanshictl status
```

Expected docked-open validation:

- `hyprctl monitors` shows both `DP-1` and `eDP-1` enabled.
- `hyprctl monitors` shows `dpmsStatus: 1` for `eDP-1`.
- `hyprctl workspaces` shows workspace `1` on `DP-1` and workspace `2` on `eDP-1`.
- `hyprctl workspacerules` shows workspace `1` bound to `DP-1` and workspace `2` bound to `eDP-1`.
- `kanshictl status` shows `docked_open_dp_only` or `docked_open_dp_hdmi`.

## Laptop Only

Use this in mobile/cafe mode with no external monitor.

| Item | Expected behavior |
| --- | --- |
| Trigger | No USB-C dock monitor and no HDMI output; also used after unplugging the docked monitor |
| Kanshi profile | `laptop` |
| Internal display | `eDP-1` enabled at preferred mode |
| External display | Disabled/not present |
| HDMI display | Disabled/not present |
| Workspaces | Workspace `1`, workspace `2`, and the active workspace moved to `eDP-1` |
| Unplug recovery | Force `eDP-1` on, force DPMS on, switch kanshi to `laptop` when `DP-1` is absent |
| Lid close | Normally suspends/locks according to system policy if no external monitor is available |
| Audio | Prefer external USB/Bluetooth device; otherwise internal speaker/headphones |

Verification:

```bash
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
kanshictl status
pactl info
```

Expected laptop validation:

- `hyprctl monitors` shows `eDP-1` enabled.
- `hyprctl monitors` shows `dpmsStatus: 1` for `eDP-1`.
- `hyprctl workspaces` shows workspace `1` and `2` on `eDP-1`.
- `hyprctl workspacerules` shows workspace `1` and `2` bound to `eDP-1`.
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
