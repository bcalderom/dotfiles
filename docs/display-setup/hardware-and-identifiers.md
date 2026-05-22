# Hardware And Identifiers

This setup depends on stable monitor identifiers. When display behavior changes after updates, verify this file against `hyprctl monitors` and `kanshictl` output.

## Connectors

| Role | Connector | Usage |
| --- | --- | --- |
| Internal laptop display | `eDP-1` | Mobile/cafe mode and HDMI mirror source |
| USB-C docked monitor | `DP-1` | Desktop workstation with laptop lid closed |
| HDMI presentation output | `HDMI-A-1` | Meeting/presentation mirror mode |

## Kanshi Output Aliases

Configured in `~/.config/kanshi/config`:

| Alias | Output identifier |
| --- | --- |
| `$INTERNAL` | `AU Optronics 0x369F Unknown` |
| `$DOCK` | `ViewSonic Corporation VX2768-2KPC W5H211040271` |
| `$HDMI` | `HDMI-A-1` |

## Hyprland Monitor Rules

Configured in `~/.config/hypr/hyprland.conf`:

| Monitor rule | Purpose |
| --- | --- |
| `desc:AU Optronics 0x369F` | Internal display fallback/default |
| `desc:ViewSonic Corporation VX2768-2KPC W5H211040271` | Docked ViewSonic monitor |
| `monitor=,preferred,auto,1` | Generic fallback for any other output |

## Verification Commands

```bash
hyprctl monitors
kanshictl status
```

## Maintenance Note

The internal display identifier differs slightly between kanshi and Hyprland today:

- kanshi: `AU Optronics 0x369F Unknown`
- Hyprland: `desc:AU Optronics 0x369F`

If profile matching becomes unreliable after an update, compare both with the live `hyprctl monitors` output and normalize where possible.
