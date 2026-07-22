# Hardware And Identifiers

The transition coordinator uses connector names; Hyprland startup defaults use stable monitor descriptors.

## Connectors

| Role | Connector | Usage |
| --- | --- | --- |
| Internal laptop display | `eDP-1` | Mobile mode and HDMI mirror source |
| USB-C monitor | `DP-1` | Docked desktop output |
| HDMI output | `HDMI-A-1` | Presentation mirror |

## Hyprland Monitor Rules

Configured in `~/.config/hypr/hyprland.conf`:

| Monitor rule | Purpose |
| --- | --- |
| `desc:AU Optronics 0x369F` | Internal display at `0x0` |
| `desc:ViewSonic Corporation VX2768-2KPC W5H211040271` | ViewSonic at `2560x1440@120.01Hz`, position `1920x0` |
| `monitor=,preferred,auto,1` | Generic output fallback |

## Verification

```bash
hyprctl monitors
hyprctl monitors all
```

If connector names or descriptors change after an update, update both `hyprland.conf` and the output constants in `lid.sh` and `lid-watch.sh`.
