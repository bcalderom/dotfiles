# Runbook

Use this to inspect or recover the display setup.

## Inspect Current State

```bash
systemctl --user status hypr-lid.service
journalctl --user -u hypr-lid.service -b
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
hyprctl activeworkspace
```

The journal should show one `hypr-lid: handling ...` entry per stable transition. Repeated alternating entries indicate connector instability.

## Restart The Coordinator

```bash
systemctl --user restart hypr-lid.service
systemctl --user status hypr-lid.service
```

Do not start `kanshi`; it would create a second output owner.

## Manual Reconciliation

Auto-detect lid state:

```bash
~/.config/hypr/scripts/lid.sh
```

Force closed-lid correction:

```bash
~/.config/hypr/scripts/lid.sh closed
```

Expected with `DP-1` connected: active and occupied workspaces are on `DP-1`, empty inactive workspaces are absent, focus is preserved, `eDP-1` is disabled, and its brightness value is restored after the disable attempt.

Force open-lid correction:

```bash
~/.config/hypr/scripts/lid.sh open
```

Expected with `DP-1` connected: both outputs are enabled, any brightness left by an interrupted transition is restored, existing external workspaces stay on `DP-1`, and the next numbered workspace is on `eDP-1`.

Expected without `DP-1`: `eDP-1` is enabled and existing workspaces return to it. If HDMI is connected, `HDMI-A-1` mirrors `eDP-1`.

The handler does not reload Hyprland when `DP-1` remains usable. If no usable output remains, it may attempt one delayed `hyprctl reload` when `eDP-1` remains inactive after an ordinary enable request. Repeated reloads are intentionally avoided because live modesets can trigger the upstream Aquamarine page-flip regression.

## Validate A Correction

```bash
hyprctl monitors
hyprctl workspaces
hyprctl workspacerules
hyprctl activeworkspace
```

## Verify Ownership

```bash
systemctl --user status hypr-lid.service
pgrep -a kanshi || true
hyprctl binds
```

Expected results:

- `hypr-lid.service` is active.
- No `kanshi` process is running.
- No lid switch bind directly invokes `lid.sh`.

## Audio Routing

```bash
~/.config/kanshi/audio-route.sh
systemctl --user restart kanshi-audio-route.service
systemctl --user status kanshi-audio-route.service
```

The audio service name does not imply display ownership.

## After Editing

```bash
bash -n ~/.config/hypr/scripts/lid.sh ~/.config/hypr/scripts/lid-watch.sh ~/.config/kanshi/audio-route.sh ~/.config/kanshi/audio-route-watch.sh
bash ~/dotfiles/scripts/desktop/hypr-lid-deploy/tests/test-lid.sh
bash ~/dotfiles/scripts/desktop/hypr-lid-deploy/tests/test-lid-watch.sh
bash ~/dotfiles/scripts/desktop/hypr-lid-deploy/tests/test-deploy.sh
~/dotfiles/scripts/desktop/hypr-lid-deploy/hypr-lid-deploy.sh --update
```

Log out and back in to validate the full Hyprland startup configuration.
