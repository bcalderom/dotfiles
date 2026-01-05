#!/usr/bin/env bash

BROWSER_CMD="${1:-brave}"
TERMINAL_CMD="${2:-alacritty}"

command -v hyprctl >/dev/null 2>&1 || exit 0

hypr_ready=0
i=0
while [ "$i" -lt 100 ]; do
  if hyprctl activeworkspace >/dev/null 2>&1; then
    hypr_ready=1
    break
  fi
  sleep 0.1
  i=$((i+1))
done

[ "$hypr_ready" -eq 1 ] || exit 0

ensure_ws1=0
i=0
while [ "$i" -lt 50 ]; do
  hyprctl dispatch workspace 1 >/dev/null 2>&1 || true
  if hyprctl activeworkspace 2>/dev/null | grep -q "workspace ID 1"; then
    ensure_ws1=1
    break
  fi
  sleep 0.05
  i=$((i+1))
done

[ "$ensure_ws1" -eq 1 ] || exit 0

brave_on_ws1() {
  hyprctl clients 2>/dev/null | awk '
    /^Window / { ws = ""; cls = "" }
    /workspace:/ { ws = $2 }
    /class:/ { cls = $2 }
    ws == "1" && cls == "brave-browser" { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

bash -lc "${BROWSER_CMD}" &

n=0
while [ "$n" -lt 100 ]; do
  if brave_on_ws1; then
    break
  fi
  sleep 0.1
  n=$((n+1))
done

hyprctl dispatch workspace 2 >/dev/null 2>&1 || true

bash -lc "${TERMINAL_CMD}" &

sleep 0.2

hyprctl dispatch workspace 1 >/dev/null 2>&1 || true
