#!/usr/bin/env bash
# Toggle "gamemode visual" en Hyprland: desactiva blur/anims/sombras para máximo FPS
set -euo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-gamemode.state"

if [[ -f "$STATE_FILE" ]]; then
    rm -f "$STATE_FILE"
    hyprctl --batch "\
        keyword animations:enabled 1;\
        keyword decoration:blur:enabled 1;\
        keyword decoration:shadow:enabled 1;\
        keyword general:gaps_in 5;\
        keyword general:gaps_out 12;\
        keyword decoration:rounding 12"
    notify-send -i applications-games "Gamemode visual" "OFF — efectos restaurados"
else
    touch "$STATE_FILE"
    hyprctl --batch "\
        keyword animations:enabled 0;\
        keyword decoration:blur:enabled 0;\
        keyword decoration:shadow:enabled 0;\
        keyword general:gaps_in 0;\
        keyword general:gaps_out 0;\
        keyword decoration:rounding 0"
    notify-send -i applications-games "Gamemode visual" "ON — máximo rendimiento"
fi
