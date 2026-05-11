#!/usr/bin/env bash
# shader-toggle.sh — cicla entre shaders de hyprshade
# Atajo: SUPER+SHIFT+S

set -euo pipefail

SHADERS=(off blue-light-filter vibrance grayscale)
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/hyprshade.idx"
mkdir -p "$(dirname "$STATE")"

command -v hyprshade >/dev/null || { notify-send "hyprshade" "no instalado"; exit 1; }

IDX=$(cat "$STATE" 2>/dev/null || echo -1)
IDX=$(( (IDX + 1) % ${#SHADERS[@]} ))
echo "$IDX" > "$STATE"

NAME="${SHADERS[$IDX]}"

if [[ "$NAME" == "off" ]]; then
    hyprshade off
    notify-send -i video-display "Shader" "Desactivado" -h "string:x-canonical-private-synchronous:shader"
else
    if hyprshade on "$NAME" 2>/dev/null; then
        notify-send -i video-display "Shader" "$NAME" -h "string:x-canonical-private-synchronous:shader"
    else
        notify-send -u low "Shader" "Shader '$NAME' no disponible" -h "string:x-canonical-private-synchronous:shader"
    fi
fi
