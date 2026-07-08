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
| Workspaces | Existing workspaces and the active workspace bound/moved to `DP-1`; empty inactive workspaces may be absent |
| Lid close | Switches kanshi to a docked profile, moves workspaces to `DP-1`, disables `eDP-1`, then restores the previously active workspace |
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
- `hyprctl workspaces` shows existing workspace entries on `DP-1`; empty inactive workspaces may be absent.
- `hyprctl workspacerules` shows workspace `1`, `2`, and `3` bound to `DP-1`.
- `hyprctl activeworkspace` shows the same workspace number that was active before closing the lid.
- `kanshictl status` shows `docked_dp_only` or `docked_dp_hdmi`.

## Docked Lid Open

Use this while still connected to the USB-C external monitor but with the laptop lid open.

| Item | Expected behavior |
| --- | --- |
| Trigger | USB-C external monitor connected and lid opened |
| Kanshi profile | `docked_open_dp_only` or `docked_open_dp_hdmi` |
| Internal display | `eDP-1` enabled at preferred mode with DPMS on |
| External display | `DP-1` remains enabled at `2560x1440@120.01Hz` |
| Workspaces | Existing `DP-1` workspaces stay on `DP-1`; the next numbered workspace is bound to `eDP-1`; active workspace number preserved |
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
- `hyprctl workspaces` shows existing `DP-1` workspaces on `DP-1`, and the next numbered workspace on `eDP-1`.
- `hyprctl workspacerules` shows existing `DP-1` workspaces bound to `DP-1`, and the next numbered workspace bound to `eDP-1` with `persistent:false`.
- `hyprctl activeworkspace` shows the same workspace number that was active before opening the lid.
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
| Workspaces | Existing workspaces and the active workspace bound/moved to `eDP-1`; empty inactive workspaces may be absent |
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
- `hyprctl workspaces` shows existing workspace entries on `eDP-1`; empty inactive workspaces may be absent.
- `hyprctl workspacerules` shows workspace `1`, `2`, and `3` bound to `eDP-1`.
- `hyprctl activeworkspace` shows the same workspace number that was active before unplug/open recovery.
- `kanshictl status` shows `laptop`.

## HDMI Mirror Presentation

Use this for meetings and presentations where the laptop display should be mirrored to HDMI.

| Item | Expected behavior |
| --- | --- |
| Trigger | HDMI display connected without the USB-C docked monitor profile taking precedence |
| Kanshi profile | `mirror` |
| Internal display | `eDP-1` enabled at preferred mode at `0x0` |
| HDMI display | `HDMI-A-1` enabled at `1920x1080@60Hz`, mirrored from `eDP-1` |
| Workspaces | Existing workspaces and the active workspace are bound to mirrored `eDP-1`; empty inactive workspaces may be absent |
| Lid close | Not the primary presentation use case; keep lid open while presenting |
| Audio | Prefer external USB/Bluetooth device; otherwise internal speaker/headphones or available HDMI sink |

Verification:

```bash
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
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
