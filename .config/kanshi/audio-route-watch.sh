#!/usr/bin/env bash

set -euo pipefail

route_script="$HOME/.config/kanshi/audio-route.sh"

[ -x "$route_script" ] || exit 0
command -v pactl >/dev/null 2>&1 || exit 0

"$route_script" >/dev/null 2>&1 || true

pactl subscribe | while IFS= read -r event; do
  case "$event" in
    *"Event 'new' on sink"*|*"Event 'remove' on sink"*|*"Event 'new' on source"*|*"Event 'remove' on source"*|*"Event 'new' on card"*|*"Event 'remove' on card"*)
      "$route_script" >/dev/null 2>&1 || true
      ;;
  esac
done
