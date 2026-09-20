#!/usr/bin/env bash
set -euo pipefail

all_mounts=(/ /home /boot)
text=""
tooltip=""
max_used=0

read_usage() {
  local path="$1"
  df --output=size,used,avail,pcent,target -B1 "$path" | tail -n 1
}

for path in "${all_mounts[@]}"; do
  read -r total used available percentage mountpoint < <(read_usage "$path")
  percentage="${percentage%%%}"
  (( percentage > max_used )) && max_used="$percentage"
  used_human="$(numfmt --to=iec-i --suffix=B "$used")"
  available_human="$(numfmt --to=iec-i --suffix=B "$available")"
  total_human="$(numfmt --to=iec-i --suffix=B "$total")"
  [[ -n "$tooltip" ]] && tooltip+=$'\n'
  tooltip+="$mountpoint: $used_human / $total_human (${percentage}%), $available_human libres"
done

class="normal"
(( max_used >= 95 )) && class="critical"
(( max_used >= 85 && max_used < 95 )) && class="warning"

jq --compact-output --null-input \
  --arg text "$text" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  '{text: $text, tooltip: $tooltip, class: $class}'
