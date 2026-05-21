#!/usr/bin/env bash

set -euo pipefail

command -v pactl >/dev/null 2>&1 || exit 0

active_dp1=0
if command -v hyprctl >/dev/null 2>&1; then
  if hyprctl monitors 2>/dev/null | grep -q "^Monitor DP-1 "; then
    active_dp1=1
  fi
fi

external_sink=""
hdmi_sink=""
speaker_sink=""
headphones_sink=""

while IFS=$'\t' read -r _ sink_name _; do
  [ -n "${sink_name:-}" ] || continue

  case "$sink_name" in
    alsa_output.usb-*|bluez_output.*)
      if [ -z "$external_sink" ]; then
        external_sink="$sink_name"
      fi
      ;;
  esac

  case "$sink_name" in
    *HiFi__HDMI1__sink)
      hdmi_sink="$sink_name"
      ;;
    *HiFi__Speaker__sink)
      speaker_sink="$sink_name"
      ;;
    *HiFi__Headphones__sink)
      headphones_sink="$sink_name"
      ;;
  esac
done < <(pactl list short sinks)

external_source=""
internal_source_mic1=""
internal_source_mic2=""
internal_source_fallback=""

while IFS=$'\t' read -r _ source_name _; do
  [ -n "${source_name:-}" ] || continue

  case "$source_name" in
    alsa_input.usb-*|bluez_input.*)
      if [ -z "$external_source" ]; then
        external_source="$source_name"
      fi
      ;;
  esac

  case "$source_name" in
    *HiFi__Mic1__source)
      if [ -z "$internal_source_mic1" ]; then
        internal_source_mic1="$source_name"
      fi
      ;;
    *HiFi__Mic2__source)
      if [ -z "$internal_source_mic2" ]; then
        internal_source_mic2="$source_name"
      fi
      ;;
    *analog-input*|*mono-fallback)
      if [ -z "$internal_source_fallback" ]; then
        internal_source_fallback="$source_name"
      fi
      ;;
  esac
done < <(pactl list short sources)

ensure_speaker_sink() {
  if [ -n "$speaker_sink" ]; then
    return
  fi

  local internal_card=""

  while IFS=$'\t' read -r _ card_name _; do
    case "$card_name" in
      alsa_card.pci-*)
        internal_card="$card_name"
        break
        ;;
    esac
  done < <(pactl list short cards)

  [ -n "$internal_card" ] || return

  pactl set-card-profile "$internal_card" "HiFi (HDMI1, HDMI2, HDMI3, Mic1, Mic2, Speaker)" >/dev/null 2>&1 || true
  sleep 0.2

  while IFS=$'\t' read -r _ sink_name _; do
    case "$sink_name" in
      *HiFi__Speaker__sink)
        speaker_sink="$sink_name"
        break
        ;;
    esac
  done < <(pactl list short sinks)
}

target_sink=""

if [ -n "$external_sink" ]; then
  target_sink="$external_sink"
elif [ "$active_dp1" -eq 1 ] && [ -n "$hdmi_sink" ]; then
  target_sink="$hdmi_sink"
else
  ensure_speaker_sink
  if [ -n "$speaker_sink" ]; then
    target_sink="$speaker_sink"
  elif [ -n "$headphones_sink" ]; then
    target_sink="$headphones_sink"
  elif [ -n "$hdmi_sink" ]; then
    target_sink="$hdmi_sink"
  fi
fi

target_source=""
if [ -n "$external_source" ]; then
  target_source="$external_source"
elif [ -n "$internal_source_mic1" ]; then
  target_source="$internal_source_mic1"
elif [ -n "$internal_source_mic2" ]; then
  target_source="$internal_source_mic2"
elif [ -n "$internal_source_fallback" ]; then
  target_source="$internal_source_fallback"
else
  while IFS= read -r line; do
    case "$line" in
      "Default Source:"*)
        target_source="${line#Default Source: }"
        break
        ;;
    esac
  done < <(pactl info)
fi

if [ -n "$target_sink" ]; then
  pactl set-default-sink "$target_sink" >/dev/null 2>&1 || true

  while IFS=$'\t' read -r sink_input_id _; do
    [ -n "${sink_input_id:-}" ] || continue
    pactl move-sink-input "$sink_input_id" "$target_sink" >/dev/null 2>&1 || true
  done < <(pactl list short sink-inputs)
fi

if [ -n "$target_source" ]; then
  pactl set-default-source "$target_source" >/dev/null 2>&1 || true

  while IFS=$'\t' read -r source_output_id _; do
    [ -n "${source_output_id:-}" ] || continue
    pactl move-source-output "$source_output_id" "$target_source" >/dev/null 2>&1 || true
  done < <(pactl list short source-outputs)
fi
